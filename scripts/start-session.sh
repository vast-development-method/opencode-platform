#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

NAME="${1:-}"
[ -n "$NAME" ] || die "Usage: $0 INSTANCE_NAME [HOST_RUNTIME_ENV_FILE] [TTL]"
HOST_ENV_FILE="${2:-/run/user/${UID}/vdm-opencode/${NAME}.env}"
TTL="${3:-$DEFAULT_SESSION_TTL}"
TTL_SECONDS="$(duration_to_seconds "$TTL")"
((TTL_SECONDS >= 60 && TTL_SECONDS <= 86400)) ||
    die "Session TTL must be between 60 seconds and 24 hours."

project_cmd info "$NAME" >/dev/null 2>&1 || die "Unknown instance: $NAME"
project_cmd start "$NAME" >/dev/null 2>&1 || true
wait_for_vm "$NAME" || die "VM agent did not become ready: $NAME"

allowed_key() {
    case "$1" in
        VDM_LLM_GATEWAY_URL|VDM_LLM_GATEWAY_TOKEN|\
        GITHUB_MCP_URL|GITHUB_MCP_TOKEN|\
        GITEA_MCP_URL|GITEA_MCP_TOKEN|\
        NEXTCLOUD_MCP_URL|NEXTCLOUD_MCP_TOKEN|\
        JOOMLA_MCP_URL|JOOMLA_MCP_TOKEN|\
        JCB_MCP_URL|JCB_MCP_TOKEN|\
        STT_MCP_URL|STT_MCP_TOKEN|\
        VDM_LOCAL_LLM_BASE_URL|VDM_LOCAL_LLM_MODEL) return 0 ;;
        *) return 1 ;;
    esac
}

validate_runtime_file() {
    local file="$1"
    local line
    local key
    [ -f "$file" ] && [ ! -L "$file" ] || die "Runtime env must be a regular non-symlink file: $file"
    [ "$(stat -c '%u' "$file")" = "$UID" ] || die "Runtime env file must be owned by UID $UID: $file"
    [ "$(stat -c '%a' "$file")" = 600 ] || die "Runtime env file must have mode 0600: $file"
    [ "$(stat -c '%h' "$file")" = 1 ] || die "Runtime env file must have exactly one hard link: $file"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ""|\#*) continue ;;
            *=*)
                key="${line%%=*}"
                [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || die "Invalid runtime variable name: $key"
                allowed_key "$key" || die "Runtime variable is not allowed: $key"
                ;;
            *) die "Invalid runtime environment line in $file" ;;
        esac
    done < "$file"
}

empty_env="$(mktemp)"
trap 'rm -f "$empty_env"' EXIT
chmod 0600 "$empty_env"
if [ -f "$HOST_ENV_FILE" ]; then
    validate_runtime_file "$HOST_ENV_FILE"
else
    HOST_ENV_FILE="$empty_env"
fi

SESSION_ID="$(date +%s)-$$"
UNIT="vdm-opencode-${SESSION_ID}"
GUEST_INPUT_DIR="/run/vdm-opencode-input"
GUEST_CREDENTIAL="${GUEST_INPUT_DIR}/${SESSION_ID}.env"
EXPIRES_EPOCH="$(($(date +%s) + TTL_SECONDS))"

cleanup() {
    project_cmd exec "$NAME" -- rm -f "$GUEST_CREDENTIAL" >/dev/null 2>&1 || true
    project_cmd exec "$NAME" -- rm -rf "/run/vdm-opencode-${SESSION_ID}" >/dev/null 2>&1 || true
    project_cmd config unset "$NAME" user.vdm.session.id >/dev/null 2>&1 || true
    project_cmd config unset "$NAME" user.vdm.session.expires_epoch >/dev/null 2>&1 || true
    project_cmd exec "$NAME" -- rm -f \
        "$AGENT_HOME/.local/share/opencode/auth.json" \
        "$AGENT_HOME/.local/share/opencode/mcp-auth.json" >/dev/null 2>&1 || true
    rm -f "$empty_env"
}
trap cleanup EXIT INT TERM

project_cmd exec "$NAME" -- install -d -o root -g root -m 0700 "$GUEST_INPUT_DIR"
project_cmd file push --mode 0600 --uid 0 --gid 0 "$HOST_ENV_FILE" "$NAME$GUEST_CREDENTIAL"
project_cmd config set "$NAME" user.vdm.session.id "$SESSION_ID"
project_cmd config set "$NAME" user.vdm.session.expires_epoch "$EXPIRES_EPOCH"

log "Starting isolated OpenCode session in $NAME (TTL: ${TTL_SECONDS}s)"
project_cmd exec "$NAME" -- systemd-run \
    --unit="$UNIT" \
    --service-type=exec \
    --pty \
    --wait \
    --collect \
    --property="User=$AGENT_USER" \
    --property="Group=$AGENT_USER" \
    --property="WorkingDirectory=$WORKSPACE_ROOT" \
    --property="RuntimeDirectory=vdm-opencode-${SESSION_ID}" \
    --property="RuntimeDirectoryMode=0700" \
    --property="RuntimeMaxSec=${TTL_SECONDS}s" \
    --property="TimeoutStopSec=20s" \
    --property="KillMode=control-group" \
    --property="SendSIGKILL=yes" \
    --property="UMask=0077" \
    --property="NoNewPrivileges=yes" \
    --property="PrivateTmp=yes" \
    --property="ProtectControlGroups=yes" \
    --property="ProtectKernelTunables=yes" \
    --property="ProtectKernelModules=yes" \
    --property="ProtectKernelLogs=yes" \
    --property="RestrictSUIDSGID=yes" \
    --property="LoadCredential=session.env:$GUEST_CREDENTIAL" \
    --setenv="VDM_SESSION_ID=$SESSION_ID" \
    --setenv="VDM_AGENT_HOME=$AGENT_HOME" \
    --setenv="VDM_WORKSPACE_ROOT=$WORKSPACE_ROOT" \
    --setenv="VDM_GITEA_BASE_URL=$GITEA_BASE_URL" \
    --setenv="VDM_NEXTCLOUD_BASE_URL=$NEXTCLOUD_BASE_URL" \
    --setenv="VDM_GITHUB_BASE_URL=$GITHUB_BASE_URL" \
    /usr/local/libexec/vdm-opencode-session
