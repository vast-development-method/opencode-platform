#!/usr/bin/env bash
set -Eeuo pipefail
AGENT_USER="${AGENT_USER:-opencode}"
AGENT_HOME="${AGENT_HOME:-/home/${AGENT_USER}}"

npm install --global \
    "${PLAYWRIGHT_MCP_PACKAGE:?PLAYWRIGHT_MCP_PACKAGE is required}" \
    "${PLAYWRIGHT_PACKAGE:?PLAYWRIGHT_PACKAGE is required}"

install -d -m 0755 /opt/ms-playwright
if [ -n "${VDM_BUILD_CACHE_DIR:-}" ]; then
    browser_cache="$VDM_BUILD_CACHE_DIR/playwright/$PLAYWRIGHT_EXPECTED_VERSION"
    install -d -m 0755 "$browser_cache"
    PLAYWRIGHT_BROWSERS_PATH="$browser_cache" \
        npx playwright install --with-deps chromium
    rm -rf /opt/ms-playwright
    install -d -m 0755 /opt/ms-playwright
    cp -a "$browser_cache/." /opt/ms-playwright/
else
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
        npx playwright install --with-deps chromium
fi

playwright_mcp_path="$(command -v playwright-mcp)"
ln -sfn "$playwright_mcp_path" /usr/local/bin/vdm-playwright-mcp

installed_playwright="$(playwright --version | awk 'NR == 1 {print $2}')"
[ "$installed_playwright" = "$PLAYWRIGHT_EXPECTED_VERSION" ] || {
    printf 'Playwright version mismatch: expected %s, got %s\n' \
        "$PLAYWRIGHT_EXPECTED_VERSION" "$installed_playwright" >&2
    exit 1
}

installed_mcp="$(npm list --global --json --depth=0 | jq -r '.dependencies["@playwright/mcp"].version')"
[ "$installed_mcp" = "$PLAYWRIGHT_MCP_EXPECTED_VERSION" ] || {
    printf 'Playwright MCP version mismatch: expected %s, got %s\n' \
        "$PLAYWRIGHT_MCP_EXPECTED_VERSION" "$installed_mcp" >&2
    exit 1
}
test -x /usr/local/bin/vdm-playwright-mcp

CONFIG="$AGENT_HOME/.config/opencode/opencode.json"
tmp="$(mktemp)"
jq '.mcp.playwright.enabled = true' "$CONFIG" > "$tmp"
install -o "$AGENT_USER" -g "$AGENT_USER" -m 0640 "$tmp" "$CONFIG"
rm -f "$tmp"
