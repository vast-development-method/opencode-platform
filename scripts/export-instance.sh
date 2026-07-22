#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

NAME="${1:-}"
OUTPUT="${2:-${NAME}-$(date +%Y%m%d).tar.zst}"
[ -n "$NAME" ] || die "Usage: $0 INSTANCE_NAME [OUTPUT.tar.zst]"

project_cmd stop "$NAME" --timeout 60 >/dev/null 2>&1 || true
project_cmd export "$NAME" "$OUTPUT" --compression zstd
sha256sum "$OUTPUT" > "${OUTPUT}.sha256"
log "Exported $OUTPUT"
