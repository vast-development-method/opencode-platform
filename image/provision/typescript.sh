#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

corepack enable
npm install --global typescript tsx "${PLAYWRIGHT_MCP_PACKAGE:-@playwright/mcp@latest}" "${PLAYWRIGHT_PACKAGE:-playwright@latest}"
npx playwright install --with-deps chromium

CONFIG=/home/opencode/.config/opencode/opencode.json
tmp="$(mktemp)"
jq '.mcp.playwright.enabled = true' "$CONFIG" > "$tmp"
install -o opencode -g opencode -m 0640 "$tmp" "$CONFIG"
rm -f "$tmp"
