from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary_csv", default="experiments/summary/ab_summary_by_scenario.csv")
    ap.add_argument("--out", default="experiments/summary/s1_s2_s3_combined.png")
    args = ap.parse_args()

    csv_path = Path(args.summary_csv)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(csv_path)
    if "scenario" not in df.columns:
        raise SystemExit(f"Missing scenario column in {csv_path}")

    # Keep only S1/S2/S3 if present
    order = ["S1", "S2", "S3"]
    df = df[df["scenario"].isin(order)].copy()
    df["scenario"] = pd.Categorical(df["scenario"], categories=order, ordered=True)
    df = df.sort_values("scenario")

    if df.empty:
        raise SystemExit("No S1/S2/S3 rows found in scenario summary CSV.")

    rps = pd.to_numeric(df.get("rps_mean"), errors="coerce")
    lat = pd.to_numeric(df.get("tpr_mean"), errors="coerce")

    fig, axes = plt.subplots(1, 2, figsize=(11, 4))

    # Throughput
    axes[0].bar(df["scenario"].astype(str), rps)
    axes[0].set_title("Throughput (RPS mean)")
    axes[0].set_ylabel("Requests / sec")
    axes[0].grid(axis="y", alpha=0.25)

    # Latency
    axes[1].bar(df["scenario"].astype(str), lat)
    axes[1].set_title("Latency (Time/request mean)")
    axes[1].set_ylabel("ms")
    axes[1].grid(axis="y", alpha=0.25)

    fig.suptitle("S1 / S2 / S3 Results (combined)")
    fig.tight_layout()
    fig.savefig(out_path, dpi=200)
    plt.close(fig)

    print(f"Wrote: {out_path}")


if __name__ == "__main__":
    main()

