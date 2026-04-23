#!/usr/bin/env bash
set -euo pipefail

# Install ApacheBench on Ubuntu (load generator machine).

sudo apt-get update -y
sudo apt-get install -y apache2-utils

ab -V

