#!/usr/bin/env bash
set -Eeuo pipefail
AGENT_USER="${AGENT_USER:-opencode}"
AGENT_HOME="${AGENT_HOME:-/home/${AGENT_USER}}"
# Joomla hosts the PHP MCP server. Agent images only need an HTTPS client.
command -v curl >/dev/null
command -v jq >/dev/null
if npm list --global --json --depth=0 | jq -e '.dependencies["@joomengine/joomla-mcp"] != null' >/dev/null; then
    npm uninstall --global --ignore-scripts --no-audit --no-fund @joomengine/joomla-mcp
fi
rm -f /usr/local/bin/vdm-joomla-mcp-http /usr/local/bin/vdm-joomla-mcp-live-test
chmod 0755 /usr/local/libexec/vdm-joomla-mcp
ln -sfn /usr/local/libexec/vdm-joomla-mcp /usr/local/bin/vdm-joomla-mcp
cat > /usr/local/bin/vdm-joomla-mcp-config-check <<'CHECK'
#!/usr/bin/env bash
set -Eeuo pipefail
exec /usr/local/bin/vdm-joomla-mcp config-check "${1:-/etc/joomla-mcp/sites.json}"
CHECK
chmod 0755 /usr/local/bin/vdm-joomla-mcp-config-check
install -d -o root -g "$AGENT_USER" -m 0750 /etc/joomla-mcp
/usr/local/bin/vdm-joomla-mcp config-check /etc/joomla-mcp/sites.readonly.example.json
rm -f /etc/joomla-mcp/sites.json
config="$AGENT_HOME/.config/opencode/opencode.json"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
jq '.mcp.joomla = {
  "type": "remote", "url": "{env:JOOMLA_MCP_URL}", "oauth": false,
  "headers": {"X-Joomla-Token": "{env:JOOMLA_MCP_SITE_TOKEN}"},
  "enabled": false, "timeout": 30000
}' "$config" > "$tmp"
install -o "$AGENT_USER" -g "$AGENT_USER" -m 0640 "$tmp" "$config"
