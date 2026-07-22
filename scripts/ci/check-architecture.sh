#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

EXPECTED="${1:?Usage: $0 amd64|arm64}"
ACTUAL="$(canonical_architecture "$(uname -m)")"
[ "$ACTUAL" = "$EXPECTED" ] || die "Runner architecture mismatch: expected $EXPECTED, got $ACTUAL"
