#!/usr/bin/env bash
set -Eeuo pipefail
PACKAGE_DIR="${1:?package directory required}"
: "${COSIGN_KEY:?Set COSIGN_KEY, preferably to openbao://vdm-opencode-release}"
command -v cosign >/dev/null 2>&1 || { printf 'cosign is required\n' >&2; exit 1; }
cosign sign-blob \
    --yes \
    --tlog-upload=false \
    --key "$COSIGN_KEY" \
    --bundle "$PACKAGE_DIR/SHA256SUMS.sigstore.json" \
    "$PACKAGE_DIR/SHA256SUMS"
