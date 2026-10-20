#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

INSTANCE="${1:-}"
OUTPUT="${2:-}"
[[ $# -ge 3 && "$INSTANCE" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] ||
    die "Usage: $0 INSTANCE NEW_HOST_DIRECTORY WORKSPACE_RELATIVE_FILE..."
shift 2
require_command python3
project_cmd info "$INSTANCE" >/dev/null 2>&1 || die "Unknown instance: $INSTANCE"
project_cmd start "$INSTANCE" >/dev/null 2>&1 || true
wait_for_vm "$INSTANCE" || die "VM agent did not become ready: $INSTANCE"

# Only an explicit list is read, as the unprivileged guest identity. Stream it
# through both validators; never recursively pull a workspace or credential tree.
project_cmd exec "$INSTANCE" --mode=non-interactive -- \
    python3 /usr/local/libexec/vdm-company-context.py export \
    "$WORKSPACE_ROOT" "$AGENT_USER" "$AGENT_HOME/.config/opencode/opencode.json" "$@" |
    python3 "$ROOT_DIR/image/files/usr/local/libexec/vdm-company-context.py" receive "$OUTPUT"
log "Review handoff saved to $OUTPUT"
