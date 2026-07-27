#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/runtime-credentials.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/joomla-mcp.sh"

NAME="${1:-}"
[ -n "$NAME" ] || die "Usage: $0 INSTANCE [HOST_RUNTIME_ENV_FILE] [SITE_ALIAS] [TTL]"
HOST_ENV_FILE="${2:-/run/user/${UID}/vdm-opencode/${NAME}.env}"
SITE_ALIAS="${3:-company}"
TTL="${4:-30m}"
(($# <= 4)) || die "Usage: $0 INSTANCE [HOST_RUNTIME_ENV_FILE] [SITE_ALIAS] [TTL]"
[[ "$SITE_ALIAS" =~ ^[A-Za-z][A-Za-z0-9_-]{0,63}$ ]] ||
    die "Unsafe Joomla site alias: $SITE_ALIAS"
TTL_SECONDS="$(duration_to_seconds "$TTL")"
((TTL_SECONDS >= 60 && TTL_SECONDS <= 86400)) ||
    die "Test TTL must be between 60 seconds and 24 hours."

project_cmd info "$NAME" >/dev/null 2>&1 || die "Unknown instance: $NAME"
project_cmd start "$NAME" >/dev/null 2>&1 || true
wait_for_vm "$NAME" || die "VM agent did not become ready: $NAME"
[ -f "$HOST_ENV_FILE" ] || die "Runtime credential file does not exist: $HOST_ENV_FILE"
validate_runtime_file "$HOST_ENV_FILE"
validate_joomla_mcp_runtime_credentials "$NAME" "$HOST_ENV_FILE"
joomla_mcp_enabled "$NAME" || die "Joomla MCP is not enabled in $NAME"
# The jq program must reach the guest unchanged.
# shellcheck disable=SC2016
project_cmd exec "$NAME" --mode=non-interactive -- \
    jq -e --arg alias "$SITE_ALIAS" '.sites[$alias] != null' \
    /etc/joomla-mcp/sites.json >/dev/null ||
    die "Joomla site alias is not configured: $SITE_ALIAS"

SESSION_ID="$(date +%s)-$$"
UNIT="vdm-joomla-read-test-${SESSION_ID}"
GUEST_INPUT_DIR="/run/vdm-opencode-input"
GUEST_CREDENTIAL="${GUEST_INPUT_DIR}/${SESSION_ID}.env"
OUTPUT_DIR="$WORKSPACE_ROOT/.artifacts/joomla-mcp/${SESSION_ID}"

cleanup() {
    project_cmd exec "$NAME" -- rm -f "$GUEST_CREDENTIAL" >/dev/null 2>&1 || true
    project_cmd exec "$NAME" -- rm -rf "/run/vdm-opencode-${SESSION_ID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

project_cmd exec "$NAME" -- install -d -o root -g root -m 0700 "$GUEST_INPUT_DIR"
project_cmd exec "$NAME" -- install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 0750 \
    "$WORKSPACE_ROOT/.artifacts" "$WORKSPACE_ROOT/.artifacts/joomla-mcp"
project_cmd file push --mode 0600 --uid 0 --gid 0 "$HOST_ENV_FILE" "$NAME$GUEST_CREDENTIAL"

log "Running the non-mutating Joomla MCP read profile in $NAME"
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
    --setenv="VDM_SESSION_MODE=joomla-read-test" \
    --setenv="VDM_AGENT_HOME=$AGENT_HOME" \
    --setenv="VDM_WORKSPACE_ROOT=$WORKSPACE_ROOT" \
    --setenv="VDM_JOOMLA_SITE_ALIAS=$SITE_ALIAS" \
    --setenv="VDM_JOOMLA_TEST_OUTPUT=$OUTPUT_DIR" \
    /usr/local/libexec/vdm-opencode-session

log "Joomla MCP read evidence: $NAME$OUTPUT_DIR"
