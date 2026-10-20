#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/image/files/usr/local/libexec/vdm-joomla-mcp"
AGENT_USER="${AGENT_USER:?configured agent account is required}"
NAME="${1:-}"
ENDPOINT="${2:-}"
SITE_ALIAS="${3:-company}"
ACCESS="${4:-readonly}"
TOKEN_ENV="${5:-}"
[[ $# -ge 2 && $# -le 5 && -n "$NAME" && -n "$ENDPOINT" ]] ||
    die "Usage: $0 INSTANCE HTTPS_BASE_OR_ENDPOINT [SITE_ALIAS] [readonly|write] [TOKEN_ENV]"
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]] || die 'Invalid instance name.'
valid_alias "$SITE_ALIAS" || die 'Use a lowercase site alias with digits/hyphens/underscores, at most 64 characters.'
ENDPOINT="${ENDPOINT%/}"
case "$ENDPOINT" in
    */api/index.php/v1/joomengine-mcp) ;;
    */api/index.php) ENDPOINT="$ENDPOINT/v1/joomengine-mcp" ;;
    *) ENDPOINT="$ENDPOINT/api/index.php/v1/joomengine-mcp" ;;
esac
validate_url "$ENDPOINT"
case "$ACCESS" in readonly|write) ;; *) die 'Access intent must be readonly or write; configure Joomla ACL to enforce it.' ;; esac
if [[ -z "$TOKEN_ENV" ]]; then
    if [[ "$SITE_ALIAS" == company ]]; then TOKEN_ENV=JOOMLA_MCP_SITE_TOKEN
    else TOKEN_ENV="JOOMLA_MCP_${SITE_ALIAS^^}_TOKEN"; TOKEN_ENV="${TOKEN_ENV//-/_}"; fi
fi
valid_token_key "$TOKEN_ENV" || die 'Invalid Joomla token variable name.'
project_cmd info "$NAME" >/dev/null 2>&1 || die "Unknown instance: $NAME"
project_cmd start "$NAME" >/dev/null 2>&1 || true
wait_for_vm "$NAME" || die "VM agent did not become ready: $NAME"
project_cmd exec "$NAME" -- test -x /usr/local/bin/vdm-joomla-mcp ||
    die 'Instance lacks native Joomla MCP integration; replace it with a current image.'
project_cmd exec "$NAME" -- install -d -o root -g "$AGENT_USER" -m 0750 /etc/joomla-mcp
project_cmd exec "$NAME" -- flock /etc/joomla-mcp/config.lock \
    /usr/local/bin/vdm-joomla-mcp configure /etc/joomla-mcp/sites.json \
    "$AGENT_HOME/.config/opencode/opencode.json" "$SITE_ALIAS" "$ENDPOINT" "$ACCESS" "$TOKEN_ENV" "$AGENT_USER"
project_cmd exec "$NAME" -- chown "root:$AGENT_USER" /etc/joomla-mcp/sites.json
runtime_file="$("$SCRIPT_DIR/create-runtime-env.sh" "$NAME")"
grep -q "^${TOKEN_ENV}=" "$runtime_file" || printf '%s=\n' "$TOKEN_ENV" >> "$runtime_file"
chmod 0600 "$runtime_file"
log "Configured Joomla MCP site $SITE_ALIAS at $ENDPOINT"
printf 'OpenCode server: joomla_%s\nCredential file: %s\nToken variable: %s\n' "$SITE_ALIAS" "$runtime_file" "$TOKEN_ENV"
printf 'Access intent: %s. Set the dedicated Joomla identity permissions on the server; this label does not restrict a privileged token.\n' "$ACCESS"
printf 'Restart the OpenCode session to load the changed connection.\n'
