#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

BACKUP="${1:-}"
NAME="${2:-}"
[ -f "$BACKUP" ] && [ -n "$NAME" ] || die "Usage: $0 BACKUP.tar.zst NEW_INSTANCE_NAME"

project_cmd import "$BACKUP" "$NAME"
log "Imported $NAME"
