#!/usr/bin/env bash
set -euo pipefail

# Export basic EC2 metrics from CloudWatch using AWS CLI.
# Usage:
#   ./scripts/export_cloudwatch_metrics.sh --instance_id i-xxxx --region ap-southeast-1 --start "2026-04-24T00:00:00Z" --end "2026-04-24T00:10:00Z" --out /tmp/cloudwatch.csv
#
# Requirements:
#   - aws CLI configured (aws configure) OR instance profile with CloudWatch read permissions.

INSTANCE_ID=""
REGION="ap-southeast-1"
START=""
END=""
OUT=""
PERIOD=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance_id) INSTANCE_ID="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --start) START="$2"; shift 2;;
    --end) END="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --period) PERIOD="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ -z "${INSTANCE_ID}" || -z "${START}" || -z "${END}" || -z "${OUT}" ]]; then
  echo "Required: --instance_id --start --end --out" >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found. Install it or run this on a machine with aws CLI configured." >&2
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

metrics=(
  CPUUtilization
  NetworkIn
  NetworkOut
)

echo "timestamp_utc,metric,value,unit" > "${OUT}"

for m in "${metrics[@]}"; do
  aws cloudwatch get-metric-statistics \
    --region "${REGION}" \
    --namespace AWS/EC2 \
    --metric-name "${m}" \
    --dimensions Name=InstanceId,Value="${INSTANCE_ID}" \
    --start-time "${START}" \
    --end-time "${END}" \
    --period "${PERIOD}" \
    --statistics Average \
    --output json > "${tmp}/${m}.json"

  python - <<'PY' "${tmp}/${m}.json" "${m}" "${OUT}"
import json, sys
from datetime import datetime, timezone

path, metric, out = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path, "r", encoding="utf-8"))
points = data.get("Datapoints", [])
points.sort(key=lambda d: d.get("Timestamp", ""))
with open(out, "a", encoding="utf-8") as f:
    for p in points:
        ts = p["Timestamp"]
        # Ensure UTC Z format
        if ts.endswith("Z"):
            ts_utc = ts
        else:
            ts_utc = datetime.fromisoformat(ts.replace("Z","")).astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        f.write(f"{ts_utc},{metric},{p.get('Average')},{p.get('Unit')}\n")
PY
done

echo "Wrote ${OUT}"

