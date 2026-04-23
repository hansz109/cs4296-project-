#!/usr/bin/env bash
set -euo pipefail

# Sample docker container CPU/mem every second.
# Usage:
#   ./scripts/collect_docker_stats.sh --out /tmp/docker_stats.csv --seconds 300

OUT=""
SECONDS=300

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2;;
    --seconds) SECONDS="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ -z "${OUT}" ]]; then
  echo "--out required" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

echo "timestamp_utc,container_name,cpu_percent,mem_usage,mem_percent,net_io,block_io,pids" > "${OUT}"

end=$(( $(date +%s) + SECONDS ))
while [[ $(date +%s) -lt $end ]]; do
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  docker stats --no-stream --format "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}},{{.PIDs}}" \
    | while IFS= read -r line; do
        echo "${ts},${line}" >> "${OUT}"
      done
  sleep 1
done

echo "Wrote ${OUT}"

