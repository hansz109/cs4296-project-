from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd
from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Inches


def add_title(doc: Document, title: str, subtitle: str) -> None:
    p = doc.add_paragraph()
    run = p.add_run(title)
    run.bold = True
    run.font.size = doc.styles["Title"].font.size
    p.style = doc.styles["Title"]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER

    p2 = doc.add_paragraph(subtitle)
    p2.alignment = WD_ALIGN_PARAGRAPH.CENTER


def add_placeholder(doc: Document, label: str) -> None:
    p = doc.add_paragraph()
    r = p.add_run(f"[WRITE THIS YOURSELF] {label}")
    r.bold = True


def add_table_from_df(doc: Document, df: pd.DataFrame, title: str) -> None:
    doc.add_paragraph(title).runs[0].bold = True
    table = doc.add_table(rows=1, cols=len(df.columns))
    table.style = "Table Grid"
    hdr = table.rows[0].cells
    for i, c in enumerate(df.columns):
        hdr[i].text = str(c)
    for _, row in df.iterrows():
        cells = table.add_row().cells
        for i, c in enumerate(df.columns):
            v = row[c]
            if isinstance(v, float):
                cells[i].text = f"{v:.3f}"
            else:
                cells[i].text = str(v)


def add_figure(doc: Document, img_path: Path, caption: str) -> None:
    if not img_path.exists():
        doc.add_paragraph(f"(Missing figure: {img_path.name})")
        return
    doc.add_picture(str(img_path), width=Inches(6.5))
    cap = doc.add_paragraph(caption)
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo_root", default=".", help="path to repo root")
    ap.add_argument("--out", default="report/CS4296_report_template.docx")
    args = ap.parse_args()

    root = Path(args.repo_root).resolve()
    out_path = (root / args.out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    summary_csv = root / "experiments" / "summary" / "ab_summary_by_profile_scenario.csv"
    thr_png = root / "experiments" / "summary" / "throughput_by_profile_scenario.png"
    lat_png = root / "experiments" / "summary" / "latency_by_profile_scenario.png"

    doc = Document()

    add_title(
        doc,
        "CS4296 Cloud Computing (Spring 2026) — Final Report",
        "Project: Benchmarking WordPress Deployment Performance with Docker (Local Profiles)",
    )

    doc.add_paragraph("Group ID: ____    Member(s): ____    Student ID(s): ____")

    doc.add_heading("Abstract (≤250 words)", level=1)
    add_placeholder(doc, "Abstract summary of goal, method, and key findings (≤250 words).")

    doc.add_heading("1. Introduction", level=1)
    add_placeholder(doc, "Background: WordPress, cloud instance selection, and containerized deployment.")
    add_placeholder(doc, "Project objective and what is benchmarked.")
    add_placeholder(doc, "Contributions / what you found (high-level).")

    doc.add_heading("2. Methodology", level=1)
    doc.add_heading("2.1 System setup", level=2)
    doc.add_paragraph(
        "Stack: Nginx (reverse proxy) → WordPress (PHP-FPM) → MySQL, deployed via Docker Compose on Windows + Docker Desktop."
    )
    doc.add_paragraph(
        "Because AWS login was unavailable, we emulate three EC2-like profiles by applying Docker CPU/memory limits: general / compute / memory."
    )
    add_placeholder(doc, "Provide your host machine specs (CPU, RAM, OS version).")

    doc.add_heading("2.2 Workloads and metrics", level=2)
    doc.add_paragraph("Load generator: ApacheBench (ab) running inside WSL Ubuntu.")
    doc.add_paragraph("Scenarios: S1 (c=10, 180s), S2 (c=50, 300s), S3 (c=100, 300s), each repeated 3 times.")
    doc.add_paragraph("Endpoints: / and /?p=1")
    doc.add_paragraph("Metrics: requests/sec, time per request (mean), failed requests; plus docker stats sampling.")

    doc.add_heading("3. Results", level=1)
    if summary_csv.exists():
        df = pd.read_csv(summary_csv)
        cols = ["profile", "scenario", "rps_mean", "rps_std", "tpr_mean", "tpr_std", "failed_sum"]
        df2 = df[[c for c in cols if c in df.columns]].copy()
        add_table_from_df(doc, df2, "Table 1. Aggregated results by profile and scenario (from artifact outputs).")
    else:
        doc.add_paragraph("(Missing summary CSV: run analysis to generate experiments/summary/...)")

    doc.add_heading("3.1 Throughput", level=2)
    add_figure(doc, thr_png, "Figure 1. Throughput (requests/sec mean) by scenario, grouped by profile.")
    add_placeholder(doc, "Explain throughput trends and why profiles differ.")

    doc.add_heading("3.2 Latency", level=2)
    add_figure(doc, lat_png, "Figure 2. Latency (time per request mean, ms) by scenario, grouped by profile.")
    add_placeholder(doc, "Explain latency trends and any bottlenecks observed.")

    doc.add_heading("4. Discussion: Validity and limitations", level=1)
    doc.add_paragraph(
        "This artifact uses local container resource limits to emulate instance-type differences. "
        "It does not capture cloud networking variability, EBS behavior, or CPU microarchitecture differences across real EC2 families."
    )
    add_placeholder(doc, "Write 3–6 bullet points on limitations and how they might affect conclusions.")

    doc.add_heading("5. Conclusion and future work", level=1)
    add_placeholder(doc, "Conclude in 3–4 sentences. Mention future work (e.g., caching, CDN, real cloud runs).")

    doc.add_heading("References", level=1)
    add_placeholder(doc, "Add references you used (websites/tools/papers). Use IEEE style if possible.")

    doc.add_page_break()
    doc.add_heading("Artifact Appendix (reproducibility)", level=1)
    doc.add_paragraph("Repository: https://github.com/hansz109/cs4296-project-")
    doc.add_paragraph("Prerequisites: Docker Desktop, WSL Ubuntu, Python 3.11+")
    doc.add_paragraph("Reproduce (high level):")
    steps = [
        r"1) Start stack: .\scripts\up_profile.ps1 -Profile general",
        r"2) Seed content: .\scripts\seed_wp.ps1",
        r"3) Install ab in WSL: .\scripts\install_ab_wsl.ps1",
        r"4) Run benchmarks: .\scripts\run_bench_wsl.ps1 -Profile <general|compute|memory> -Scenario <S1|S2|S3> -Repeat 3",
        r"5) Analyze: python scripts\analyze_results.py --results_dir experiments\results --out_dir experiments\summary",
    ]
    for s in steps:
        doc.add_paragraph(s, style="List Number")

    doc.add_paragraph("Expected outputs:")
    outs = [
        r"- experiments\results\<RUN_ID>\ab_*.txt, meta.txt, docker_stats.csv",
        r"- experiments\summary\ab_summary_by_profile_scenario.csv",
        r"- experiments\summary\throughput_by_profile_scenario.png",
        r"- experiments\summary\latency_by_profile_scenario.png",
    ]
    for o in outs:
        doc.add_paragraph(o, style="List Bullet")

    doc.save(out_path)
    print(f"Wrote: {out_path}")


if __name__ == "__main__":
    main()

