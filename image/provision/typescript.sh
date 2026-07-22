#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

corepack enable
npm install --global \
    "${TYPESCRIPT_PACKAGE:?TYPESCRIPT_PACKAGE is required}" \
    "${TSX_PACKAGE:?TSX_PACKAGE is required}" \
    "${PLAYWRIGHT_MCP_PACKAGE:?PLAYWRIGHT_MCP_PACKAGE is required}" \
    "${PLAYWRIGHT_PACKAGE:?PLAYWRIGHT_PACKAGE is required}"
install -d -m 0755 /opt/ms-playwright
PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright npx playwright install --with-deps chromium

playwright_mcp_path="$(command -v playwright-mcp)"
ln -sfn "$playwright_mcp_path" /usr/local/bin/vdm-playwright-mcp

[ "$(tsc --version | awk '{print $2}')" = "$TYPESCRIPT_EXPECTED_VERSION" ]
[ "$(tsx --version | awk 'NR == 1 {print $2}')" = "$TSX_EXPECTED_VERSION" ]
[ "$(playwright --version | awk '{print $2}')" = "$PLAYWRIGHT_EXPECTED_VERSION" ]

installed_mcp="$(npm list --global --json --depth=0 | jq -r '.dependencies["@playwright/mcp"].version')"
[ "$installed_mcp" = "$PLAYWRIGHT_MCP_EXPECTED_VERSION" ]
test -x /usr/local/bin/vdm-playwright-mcp

CONFIG=/home/opencode/.config/opencode/opencode.json
tmp="$(mktemp)"
jq '.mcp.playwright.enabled = true' "$CONFIG" > "$tmp"
install -o opencode -g opencode -m 0640 "$tmp" "$CONFIG"
rm -f "$tmp"
