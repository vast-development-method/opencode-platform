#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

NAME="${1:-}"
SERVER="${2:-}"
STATE="${3:-}"
if [ -z "$NAME" ] || [ -z "$SERVER" ] || [ -z "$STATE" ]; then
    die "Usage: $0 INSTANCE SERVER true|false"
fi
case "$STATE" in true|false) ;; *) die "State must be true or false" ;; esac

# The single-quoted program is evaluated inside the guest, where the injected variables exist.
# shellcheck disable=SC2016
project_cmd exec "$NAME" --env "MCP_SERVER=$SERVER" --env "MCP_STATE=$STATE" -- bash -c '
set -Eeuo pipefail
config="/home/opencode/.config/opencode/opencode.json"
jq -e --arg server "$MCP_SERVER" ".mcp[\$server] != null" "$config" >/dev/null || {
    printf "Unknown MCP server: %s\n" "$MCP_SERVER" >&2
    exit 1
}

if [ "$MCP_STATE" = true ]; then
    server_type="$(jq -r --arg server "$MCP_SERVER" ".mcp[\$server].type" "$config")"
    if [ "$server_type" = local ]; then
        command_path="$(jq -r --arg server "$MCP_SERVER" ".mcp[\$server].command[0] // empty" "$config")"
        [ -n "$command_path" ] && [ -x "$command_path" ] || {
            printf "Local MCP executable is unavailable for %s: %s\n" "$MCP_SERVER" "$command_path" >&2
            exit 1
        }
    fi
    if [ "$MCP_SERVER" = joomla ]; then
        test -r /etc/joomla-mcp/sites.json || {
            printf "Configure the Joomla target before enabling Joomla MCP.\n" >&2
            exit 1
        }
        /usr/local/bin/vdm-joomla-mcp-config-check /etc/joomla-mcp/sites.json
    fi
fi

tmp="$(mktemp)"
jq --arg server "$MCP_SERVER" --argjson state "$MCP_STATE" \
  ".mcp[\$server].enabled = \$state" \
  "$config" > "$tmp"
install -o opencode -g opencode -m 0640 "$tmp" "$config"
rm -f "$tmp"
'
