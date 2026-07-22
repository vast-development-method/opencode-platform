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
tmp="$(mktemp)"
jq --arg server "$MCP_SERVER" --argjson state "$MCP_STATE" \
  "if .mcp[\$server] == null then error(\"Unknown MCP server: \" + \$server) else .mcp[\$server].enabled = \$state end" \
  "$config" > "$tmp"
install -o opencode -g opencode -m 0640 "$tmp" "$config"
rm -f "$tmp"
'
