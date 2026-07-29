#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    python3-dev \
    python3-pytest

sudo -u opencode -H env \
    PIPX_HOME=/home/opencode/.local/share/pipx \
    PIPX_BIN_DIR=/home/opencode/.local/bin \
    PIP_CACHE_DIR="${PIP_CACHE_DIR:-/home/opencode/.cache/pip}" \
    pipx install --force "${RUFF_PACKAGE:?RUFF_PACKAGE is required}"
sudo -u opencode -H env \
    PIPX_HOME=/home/opencode/.local/share/pipx \
    PIPX_BIN_DIR=/home/opencode/.local/bin \
    PIP_CACHE_DIR="${PIP_CACHE_DIR:-/home/opencode/.cache/pip}" \
    pipx install --force "${MYPY_PACKAGE:?MYPY_PACKAGE is required}"

installed_ruff="$(
    sudo -u opencode -H /home/opencode/.local/bin/ruff --version |
        awk 'NR == 1 {print $2}'
)"
installed_mypy="$(
    sudo -u opencode -H /home/opencode/.local/bin/mypy --version |
        awk 'NR == 1 {print $2}'
)"
[ "$installed_ruff" = "$RUFF_EXPECTED_VERSION" ] || {
    printf 'Ruff version mismatch: expected %s, got %s\n' \
        "$RUFF_EXPECTED_VERSION" "$installed_ruff" >&2
    exit 1
}
[ "$installed_mypy" = "$MYPY_EXPECTED_VERSION" ] || {
    printf 'mypy version mismatch: expected %s, got %s\n' \
        "$MYPY_EXPECTED_VERSION" "$installed_mypy" >&2
    exit 1
}
