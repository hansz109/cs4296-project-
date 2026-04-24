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

def parse_meta(path: Path) -> dict:
    if not path.exists():
        return {}
    out = {}
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


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
        meta = parse_meta(run_dir / "meta.txt")
        scenario = meta.get("scenario") or (run_dir.name.split("_")[-1] if "_" in run_dir.name else "")
        profile = meta.get("profile") or ""
        for f in run_dir.glob("ab_*.txt"):
            rec = parse_ab_file(f)
            rec.update({"run_id": run_dir.name, "scenario": scenario, "profile": profile})
            rows.append(rec)

    if not rows:
        raise SystemExit(f"No ab_*.txt found under {results_dir}")

    df = pd.DataFrame(rows)
    df.to_csv(out_dir / "ab_parsed.csv", index=False)

    # Scenario-only aggregation (mean over repeats/paths/profiles with real metrics)
    df_s = df.copy()
    df_s["rps"] = pd.to_numeric(df_s["rps"], errors="coerce")
    df_s["time_per_request_ms"] = pd.to_numeric(df_s["time_per_request_ms"], errors="coerce")
    df_s["failed_requests"] = pd.to_numeric(df_s["failed_requests"], errors="coerce")
    df_s = df_s[df_s["rps"].notna()].copy()

    agg_s = (
        df_s.groupby(["scenario"], dropna=False)
        .agg(
            rps_mean=("rps", "mean"),
            rps_std=("rps", "std"),
            tpr_mean=("time_per_request_ms", "mean"),
            tpr_std=("time_per_request_ms", "std"),
            failed_sum=("failed_requests", "sum"),
        )
        .reset_index()
    )
    agg_s.to_csv(out_dir / "ab_summary_by_scenario.csv", index=False)

    # Scenario-only plots (single series)
    scenarios_s = sorted([s for s in agg_s["scenario"].unique() if isinstance(s, str)])
    agg_s = agg_s.set_index("scenario").reindex(scenarios_s).reset_index()

    plt.figure(figsize=(8, 4))
    plt.bar(agg_s["scenario"], agg_s["rps_mean"])
    plt.ylabel("Requests per second (mean)")
    plt.title("Throughput by scenario")
    plt.tight_layout()
    plt.savefig(out_dir / "throughput_by_scenario.png", dpi=160)
    plt.close()

    plt.figure(figsize=(8, 4))
    plt.bar(agg_s["scenario"], agg_s["tpr_mean"])
    plt.ylabel("Time per request (ms, mean)")
    plt.title("Latency (mean) by scenario")
    plt.tight_layout()
    plt.savefig(out_dir / "latency_by_scenario.png", dpi=160)
    plt.close()

    # Aggregate by profile + scenario (mean over repeats and paths)
    agg = df.groupby(["profile", "scenario"], dropna=False).agg(
        rps_mean=("rps", "mean"),
        rps_std=("rps", "std"),
        tpr_mean=("time_per_request_ms", "mean"),
        tpr_std=("time_per_request_ms", "std"),
        failed_sum=("failed_requests", "sum"),
    ).reset_index()
    agg.to_csv(out_dir / "ab_summary_by_profile_scenario.csv", index=False)

    # Plot: throughput by scenario, separated by profile
    profiles = [p for p in agg["profile"].unique() if isinstance(p, str)]
    scenarios = [s for s in agg["scenario"].unique() if isinstance(s, str)]
    scenarios = sorted(scenarios)
    profiles = sorted(profiles)

    def pivot(col: str) -> pd.DataFrame:
        return agg.pivot(index="scenario", columns="profile", values=col).reindex(scenarios)

    thr = pivot("rps_mean")
    lat = pivot("tpr_mean")

    ax = thr.plot(kind="bar", figsize=(9, 4))
    ax.set_ylabel("Requests per second (mean)")
    ax.set_title("Throughput by scenario (by profile)")
    plt.tight_layout()
    plt.savefig(out_dir / "throughput_by_profile_scenario.png", dpi=160)
    plt.close()

    ax = lat.plot(kind="bar", figsize=(9, 4))
    ax.set_ylabel("Time per request (ms, mean)")
    ax.set_title("Latency (mean) by scenario (by profile)")
    plt.tight_layout()
    plt.savefig(out_dir / "latency_by_profile_scenario.png", dpi=160)
    plt.close()

    print(f"Wrote: {out_dir}")


if __name__ == "__main__":
    main()

