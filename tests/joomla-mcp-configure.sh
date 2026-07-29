#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
runtime_base="$(mktemp -d /dev/shm/vdm-opencode-test.XXXXXX)"
instance="joomla-config-test-$$"
runtime_file="${runtime_base}/vdm-opencode/${instance}.env"
trap 'rm -rf "$tmp_dir" "$runtime_base"' EXIT

export PATH="$ROOT_DIR/tests/fixtures/joomla:$PATH"
export CAPTURE_CONFIG="$tmp_dir/config.json"
export VDM_RUNTIME_BASE="$runtime_base"

"$ROOT_DIR/scripts/configure-joomla-mcp.sh" \
    "$instance" https://www.example.com company readonly >/dev/null
jq -e '
  .defaultSite == "company"
  and (.sites.company.toolsets | index("content.write") | not)
  and (has("approval") | not)
' "$CAPTURE_CONFIG" >/dev/null

"$ROOT_DIR/scripts/configure-joomla-mcp.sh" \
    "$instance" https://www.example.com company content >/dev/null
jq -e '
  (.sites.company.toolsets | index("content.write") != null)
  and .approval.allowIndefinite == false
  and (.sites.company.api | has("updateTokenEnv") | not)
' "$CAPTURE_CONFIG" >/dev/null

"$ROOT_DIR/scripts/configure-joomla-mcp.sh" \
    "$instance" https://www.example.com company full >/dev/null
jq -e '
  (.sites.company.toolsets | index("core-update") != null)
  and .sites.company.api.updateTokenEnv == "JOOMLA_MCP_UPDATE_TOKEN"
' "$CAPTURE_CONFIG" >/dev/null

for key in JOOMLA_MCP_SITE_TOKEN JOOMLA_MCP_APPROVAL_SECRET JOOMLA_MCP_UPDATE_TOKEN; do
    [ "$(grep -c "^${key}=" "$runtime_file")" = 1 ]
done
[ "$(stat -c '%a' "$runtime_file")" = 600 ]

if "$ROOT_DIR/scripts/configure-joomla-mcp.sh" \
    "$instance" http://www.example.com company readonly >/dev/null 2>&1; then
    printf 'An insecure Joomla origin was accepted.\n' >&2
    exit 1
fi

printf 'Joomla MCP configuration tests passed.\n'
