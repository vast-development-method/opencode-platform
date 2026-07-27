#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

NAME="${1:-}"
BASE_URL="${2:-}"
SITE_ALIAS="${3:-company}"
PROFILE="${4:-readonly}"

if (($# > 4)); then
    die "Usage: $0 INSTANCE HTTPS_BASE_URL [SITE_ALIAS] [readonly|content|admin|full]"
fi
if [ -z "$NAME" ] || [ -z "$BASE_URL" ]; then
    die "Usage: $0 INSTANCE HTTPS_BASE_URL [SITE_ALIAS] [readonly|content|admin|full]"
fi
[[ "$SITE_ALIAS" =~ ^[A-Za-z][A-Za-z0-9_-]{0,63}$ ]] ||
    die "Unsafe Joomla site alias: $SITE_ALIAS"

BASE_URL="${BASE_URL%/}"
[[ "$BASE_URL" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?$ ]] ||
    die "Joomla base URL must be one HTTPS origin without credentials, path, query, or fragment"
[[ "$BASE_URL" != *".."* ]] || die "Joomla base URL contains an invalid hostname"
if [[ "$BASE_URL" =~ :([0-9]+)$ ]]; then
    port="${BASH_REMATCH[1]}"
    ((port >= 1 && port <= 65535)) || die "Joomla HTTPS port is outside 1-65535"
fi

needs_approval=false
needs_update=false
case "$PROFILE" in
    readonly)
        toolsets='[
          "discovery",
          "content.read",
          "structure.read",
          "media.read",
          "users.read",
          "extensions.read",
          "configuration.read",
          "maintenance.read"
        ]'
        ;;
    content)
        needs_approval=true
        toolsets='[
          "discovery",
          "content.read",
          "content.write",
          "structure.read",
          "structure.write",
          "media.read",
          "media.write",
          "users.read",
          "extensions.read",
          "configuration.read",
          "maintenance.read"
        ]'
        ;;
    admin)
        needs_approval=true
        toolsets='[
          "discovery",
          "content.read",
          "content.write",
          "structure.read",
          "structure.write",
          "media.read",
          "media.write",
          "users.read",
          "users.admin",
          "extensions.read",
          "extensions.admin",
          "configuration.read",
          "configuration.write",
          "maintenance.read",
          "maintenance.admin"
        ]'
        ;;
    full)
        needs_approval=true
        needs_update=true
        toolsets='[
          "discovery",
          "content.read",
          "content.write",
          "structure.read",
          "structure.write",
          "media.read",
          "media.write",
          "users.read",
          "users.admin",
          "extensions.read",
          "extensions.admin",
          "configuration.read",
          "configuration.write",
          "maintenance.read",
          "maintenance.admin",
          "core-update"
        ]'
        ;;
    *) die "Profile must be one of: readonly, content, admin, full" ;;
esac

project_cmd info "$NAME" >/dev/null 2>&1 || die "Unknown instance: $NAME"
project_cmd start "$NAME" >/dev/null 2>&1 || true
wait_for_vm "$NAME" || die "VM agent did not become ready: $NAME"
project_cmd exec "$NAME" -- test -x /usr/local/bin/vdm-joomla-mcp ||
    die "Instance $NAME does not contain the Joomla MCP capability; use a current php or full image"

config_file="$(mktemp)"
guest_config="/run/vdm-joomla-mcp-config-$$.json"
guest_target=/etc/joomla-mcp/sites.json
guest_target_temp=/etc/joomla-mcp/.sites.json.new
cleanup() {
    rm -f "$config_file"
    project_cmd exec "$NAME" -- rm -f "$guest_config" "$guest_target_temp" >/dev/null 2>&1 || true
}
trap cleanup EXIT

jq -n \
    --arg alias "$SITE_ALIAS" \
    --arg base_url "$BASE_URL" \
    --argjson toolsets "$toolsets" \
    --argjson needs_approval "$needs_approval" \
    --argjson needs_update "$needs_update" \
    '{
      defaultSite: $alias,
      sites: {
        ($alias): {
          toolsets: $toolsets,
          api: (
            {
              baseUrl: $base_url,
              tokenEnv: "JOOMLA_MCP_SITE_TOKEN",
              timeoutMs: 30000,
              maxResponseBytes: 5242880,
              maxPageSize: 100
            }
            + (
              if $needs_update
              then {updateTokenEnv: "JOOMLA_MCP_UPDATE_TOKEN"}
              else {}
              end
            )
          )
        }
      }
    }
    + (
      if $needs_approval
      then {
        approval: {
          secretEnv: "JOOMLA_MCP_APPROVAL_SECRET",
          ttlMs: 300000,
          requestTtlMs: 300000,
          allowIndefinite: false
        }
      }
      else {}
      end
    )' > "$config_file"
chmod 0600 "$config_file"

project_cmd exec "$NAME" -- install -d -o root -g "$AGENT_USER" -m 0750 /etc/joomla-mcp
project_cmd file push --mode 0600 --uid 0 --gid 0 "$config_file" "$NAME$guest_config"
project_cmd exec "$NAME" -- /usr/local/bin/vdm-joomla-mcp-config-check "$guest_config"
project_cmd exec "$NAME" -- install -o root -g "$AGENT_USER" -m 0640 \
    "$guest_config" "$guest_target_temp"
project_cmd exec "$NAME" -- mv -f "$guest_target_temp" "$guest_target"

"$SCRIPT_DIR/mcp-toggle.sh" "$NAME" joomla true
runtime_file="$("$SCRIPT_DIR/create-runtime-env.sh" "$NAME")"

log "Configured local Joomla MCP for $SITE_ALIAS at $BASE_URL"
printf 'Profile: %s\n' "$PROFILE"
printf 'Credential file: %s\n' "$runtime_file"
printf 'Set JOOMLA_MCP_SITE_TOKEN before starting the session.\n'
if [ "$needs_approval" = true ]; then
    printf 'Set JOOMLA_MCP_APPROVAL_SECRET to at least 32 random characters for guarded writes.\n'
fi
if [ "$needs_update" = true ]; then
    printf 'Set the separately scoped JOOMLA_MCP_UPDATE_TOKEN before using core-update.\n'
fi
