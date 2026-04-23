#!/usr/bin/env bash
set -euo pipefail

# Local load generator using ApacheBench (ab).
# Usage:
#   ./scripts/run_bench_local.sh --base_url "http://1.2.3.4" --scenario S2 --repeat 3

BASE_URL=""
SCENARIO=""
REPEAT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base_url) BASE_URL="$2"; shift 2;;
    --scenario) SCENARIO="$2"; shift 2;;
    --repeat) REPEAT="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ -z "${BASE_URL}" || -z "${SCENARIO}" ]]; then
  echo "Missing required args." >&2
  exit 1
fi

cd "$(dirname "$0")/.."

if ! command -v ab >/dev/null 2>&1; then
  echo "ab not found. Install apache2-utils (Ubuntu) or ApacheBench on your load generator machine." >&2
  exit 2
fi

MATRIX="experiments/matrix.yaml"
if [[ ! -f "${MATRIX}" ]]; then
  echo "Missing ${MATRIX}" >&2
  exit 3
fi

python - <<'PY'
import sys, yaml
from pathlib import Path
m = yaml.safe_load(Path("experiments/matrix.yaml").read_text(encoding="utf-8"))
sc = sys.argv[1]
if sc not in m["scenarios"]:
    raise SystemExit(f"Scenario not found: {sc}")
print(m["scenarios"][sc]["concurrency"])
print(m["scenarios"][sc]["duration_s"])
print("\n".join(m["scenarios"][sc]["paths"]))
PY "${SCENARIO}" > /tmp/cs4296_scenario.txt

CONCURRENCY="$(sed -n '1p' /tmp/cs4296_scenario.txt | tr -d '\r')"
DURATION_S="$(sed -n '2p' /tmp/cs4296_scenario.txt | tr -d '\r')"
PATHS="$(tail -n +3 /tmp/cs4296_scenario.txt | tr -d '\r')"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)_${SCENARIO}"
OUT_DIR="experiments/results/${RUN_ID}"
mkdir -p "${OUT_DIR}"

echo "run_id=${RUN_ID}" | tee "${OUT_DIR}/meta.txt" >/dev/null
echo "base_url=${BASE_URL}" | tee -a "${OUT_DIR}/meta.txt" >/dev/null
echo "scenario=${SCENARIO}" | tee -a "${OUT_DIR}/meta.txt" >/dev/null
echo "concurrency=${CONCURRENCY}" | tee -a "${OUT_DIR}/meta.txt" >/dev/null
echo "duration_s=${DURATION_S}" | tee -a "${OUT_DIR}/meta.txt" >/dev/null

N_REQUESTS=$(( DURATION_S * CONCURRENCY ))

i=1
while [[ $i -le $REPEAT ]]; do
  for p in ${PATHS}; do
    URL="${BASE_URL}${p}"
    SAFE_PATH="$(echo "${p}" | sed 's#[^a-zA-Z0-9]#_#g')"
    OUT="${OUT_DIR}/ab_${SAFE_PATH}_rep${i}.txt"
    echo "Running ab: ${URL} (c=${CONCURRENCY}, n=${N_REQUESTS})"
    ab -k -c "${CONCURRENCY}" -n "${N_REQUESTS}" "${URL}" > "${OUT}" || true
  done
  i=$((i+1))
done

echo "Saved results to ${OUT_DIR}"

