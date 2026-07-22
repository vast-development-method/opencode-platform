#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    python3-dev \
    python3-pytest

sudo -u opencode -H uv tool install --force "${RUFF_PACKAGE:?RUFF_PACKAGE is required}"
sudo -u opencode -H uv tool install --force "${MYPY_PACKAGE:?MYPY_PACKAGE is required}"

[ "$(sudo -u opencode -H /home/opencode/.local/bin/ruff --version | awk '{print $2}')" = "$RUFF_EXPECTED_VERSION" ]
[ "$(sudo -u opencode -H /home/opencode/.local/bin/mypy --version | awk '{print $2}')" = "$MYPY_EXPECTED_VERSION" ]
