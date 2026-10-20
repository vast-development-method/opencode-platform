#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

INSTANCE="${1:-}"
SOURCE="${2:-}"
REVISION="${3:-HEAD}"
[[ $# -ge 2 && $# -le 3 && "$INSTANCE" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] ||
    die "Usage: $0 INSTANCE LOCAL_GIT_REPOSITORY [COMMIT_OR_REF]"
[ -d "$SOURCE" ] || die "Company source must be an existing local Git repository"
require_command python3
require_command git
require_command jq

helper="$ROOT_DIR/image/files/usr/local/libexec/vdm-company-context.py"
temporary="$(mktemp -d)"
guest_bundle="/run/vdm-company-input-${temporary##*/}.json"
cleanup() {
    rm -rf -- "$temporary"
    project_cmd exec "$INSTANCE" -- rm -f -- "$guest_bundle" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
python3 "$helper" source "$SOURCE" "$REVISION" > "$temporary/snapshot.json"
chmod 0600 "$temporary/snapshot.json"

project_cmd info "$INSTANCE" >/dev/null 2>&1 || die "Unknown instance: $INSTANCE"
project_cmd start "$INSTANCE" >/dev/null 2>&1 || true
wait_for_vm "$INSTANCE" || die "VM agent did not become ready: $INSTANCE"
project_cmd exec "$INSTANCE" -- test -f /usr/local/libexec/vdm-company-context.py ||
    die "Rebuild this worker with company-context support before synchronizing instructions"
project_cmd file push --mode 0600 --uid 0 --gid 0 \
    "$temporary/snapshot.json" "$INSTANCE$guest_bundle"
project_cmd exec "$INSTANCE" -- python3 /usr/local/libexec/vdm-company-context.py \
    install "$guest_bundle" "$AGENT_HOME/.config/opencode/opencode.json"
project_cmd exec "$INSTANCE" -- python3 /usr/local/libexec/vdm-company-context.py \
    verify "$AGENT_HOME/.config/opencode/opencode.json" --required
log "Company instructions synchronized from committed Git content"
jq -r '"Company: \(.name)\nCommit: \(.revision)\nSnapshot: \(.snapshot)"' "$temporary/snapshot.json"
