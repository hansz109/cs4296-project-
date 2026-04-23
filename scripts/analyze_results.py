import argparse
import re
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


AB_RPS_RE = re.compile(r"Requests per second:\s+([0-9.]+)\s+\[#/sec\]")
AB_TPR_RE = re.compile(r"Time per request:\s+([0-9.]+)\s+\[ms\]\s+\(mean\)")
AB_FAILED_RE = re.compile(r"Failed requests:\s+(\d+)")


def parse_ab_file(path: Path) -> dict:
    txt = path.read_text(encoding="utf-8", errors="ignore")
    rps = float(AB_RPS_RE.search(txt).group(1)) if AB_RPS_RE.search(txt) else None
    tpr = float(AB_TPR_RE.search(txt).group(1)) if AB_TPR_RE.search(txt) else None
    failed = int(AB_FAILED_RE.search(txt).group(1)) if AB_FAILED_RE.search(txt) else None
    return {"file": path.name, "rps": rps, "time_per_request_ms": tpr, "failed_requests": failed}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results_dir", required=True)
    ap.add_argument("--out_dir", required=True)
    args = ap.parse_args()

    results_dir = Path(args.results_dir)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    for run_dir in sorted([p for p in results_dir.iterdir() if p.is_dir()]):
        scenario = run_dir.name.split("_")[-1] if "_" in run_dir.name else ""
        for f in run_dir.glob("ab_*.txt"):
            rec = parse_ab_file(f)
            rec.update({"run_id": run_dir.name, "scenario": scenario})
            rows.append(rec)

    if not rows:
        raise SystemExit(f"No ab_*.txt found under {results_dir}")

    df = pd.DataFrame(rows)
    df.to_csv(out_dir / "ab_parsed.csv", index=False)

    # Aggregate by scenario (mean over repeats and paths)
    agg = df.groupby(["scenario"], dropna=False).agg(
        rps_mean=("rps", "mean"),
        rps_std=("rps", "std"),
        tpr_mean=("time_per_request_ms", "mean"),
        tpr_std=("time_per_request_ms", "std"),
        failed_sum=("failed_requests", "sum"),
    ).reset_index()
    agg.to_csv(out_dir / "ab_summary_by_scenario.csv", index=False)

    # Simple plots
    plt.figure(figsize=(8, 4))
    plt.bar(agg["scenario"], agg["rps_mean"])
    plt.ylabel("Requests per second (mean)")
    plt.title("Throughput by scenario")
    plt.tight_layout()
    plt.savefig(out_dir / "throughput_by_scenario.png", dpi=160)
    plt.close()

    plt.figure(figsize=(8, 4))
    plt.bar(agg["scenario"], agg["tpr_mean"])
    plt.ylabel("Time per request (ms, mean)")
    plt.title("Latency (mean) by scenario")
    plt.tight_layout()
    plt.savefig(out_dir / "latency_by_scenario.png", dpi=160)
    plt.close()

    print(f"Wrote: {out_dir}")


if __name__ == "__main__":
    main()

