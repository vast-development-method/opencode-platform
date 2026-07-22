#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    python3-dev \
    python3-pytest

for tool in ruff mypy; do
    if ! sudo -u opencode -H uv tool list | grep -q "^${tool} "; then
        sudo -u opencode -H uv tool install "$tool"
    fi
done
