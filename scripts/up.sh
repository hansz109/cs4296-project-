#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found. Run scripts/install_docker_ubuntu.sh first." >&2
  exit 1
fi

docker compose pull
docker compose up -d

echo "Stack is starting. Try: http://<your_ec2_ip>/"
docker compose ps

