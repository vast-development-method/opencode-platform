#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

NAME="${1:-}"
[ -n "$NAME" ] || die "Usage: $0 INSTANCE_NAME [HOST_RUNTIME_ENV_FILE]"
HOST_ENV_FILE="${2:-/run/user/${UID}/vdm-opencode/${NAME}.env}"

project_cmd info "$NAME" >/dev/null 2>&1 || die "Unknown instance: $NAME"
project_cmd start "$NAME" >/dev/null 2>&1 || true
wait_for_vm "$NAME" || die "VM agent did not become ready: $NAME"

declare -a EXEC_ENV
if [ -f "$HOST_ENV_FILE" ]; then
    [ "$(stat -c '%a' "$HOST_ENV_FILE")" = 600 ] || die "Runtime env file must have mode 0600: $HOST_ENV_FILE"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ""|\#*) continue ;;
            *=*) EXEC_ENV+=(--env "$line") ;;
            *) die "Invalid runtime environment line in $HOST_ENV_FILE" ;;
        esac
    done < "$HOST_ENV_FILE"
fi

SESSION_ID="$(date +%s)-$$"
GUEST_RUNTIME="/run/vdm-opencode-session/${SESSION_ID}"

cleanup() {
    project_cmd exec "$NAME" -- rm -rf "$GUEST_RUNTIME" >/dev/null 2>&1 || true
    project_cmd exec "$NAME" -- rm -f \
        "$AGENT_HOME/.local/share/opencode/auth.json" \
        "$AGENT_HOME/.local/share/opencode/mcp-auth.json" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

project_cmd exec "$NAME" -- install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 0700 "$GUEST_RUNTIME/data"

log "Starting ephemeral OpenCode session in $NAME"
project_cmd exec "$NAME" \
    "${EXEC_ENV[@]}" \
    --env "HOME=$AGENT_HOME" \
    --env "USER=$AGENT_USER" \
    --env "LOGNAME=$AGENT_USER" \
    --env "PATH=$AGENT_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    --env "XDG_DATA_HOME=$GUEST_RUNTIME/data" \
    --env "VDM_GITEA_BASE_URL=$GITEA_BASE_URL" \
    --env "VDM_NEXTCLOUD_BASE_URL=$NEXTCLOUD_BASE_URL" \
    --env "VDM_GITHUB_BASE_URL=$GITHUB_BASE_URL" \
    --cwd "$WORKSPACE_ROOT" \
    -- runuser -u "$AGENT_USER" --preserve-environment -- "$AGENT_HOME/.local/bin/opencode"
