#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

INSTANCE="${1:?instance required}"
VARIANT="${2:?variant required}"

guest_output() {
    project_cmd exec "$INSTANCE" --mode=non-interactive -- "$@" | tr -d '\r'
}

assert_version() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    [ "$actual" = "$expected" ] || die "$label version mismatch: expected $expected, got $actual"
}

project_cmd exec "$INSTANCE" -- test -x "$AGENT_HOME/.local/bin/opencode"
project_cmd exec "$INSTANCE" -- test -d "$WORKSPACE_ROOT"
project_cmd exec "$INSTANCE" -- test -f /etc/opencode/opencode.json
project_cmd exec "$INSTANCE" -- test -f /etc/vdm-opencode-platform/build.json
project_cmd exec "$INSTANCE" -- test -f /usr/local/libexec/vdm-company-context.py
project_cmd exec "$INSTANCE" -- python3 /usr/local/libexec/vdm-company-context.py verify \
    "$AGENT_HOME/.config/opencode/opencode.json"
project_cmd exec "$INSTANCE" -- jq empty /etc/opencode/opencode.json
# The jq program must reach the guest unchanged.
# shellcheck disable=SC2016
project_cmd exec "$INSTANCE" -- jq -e --arg variant "$VARIANT" '.variant == $variant' /etc/vdm-opencode-platform/build.json >/dev/null
project_cmd exec "$INSTANCE" -- test ! -e "$AGENT_HOME/.local/share/opencode/auth.json"
project_cmd exec "$INSTANCE" -- test ! -e "$AGENT_HOME/.local/share/opencode/mcp-auth.json"
project_cmd exec "$INSTANCE" -- test ! -e /opt/vdm-build
project_cmd exec "$INSTANCE" -- test ! -s /etc/machine-id
project_cmd exec "$INSTANCE" -- bash -c '! compgen -G "/etc/ssh/ssh_host_*" >/dev/null'
# This expression is intentionally expanded by the guest shell.
# shellcheck disable=SC2016
project_cmd exec "$INSTANCE" --env "AGENT_HOME=$AGENT_HOME" -- bash -c \
    '! find "$AGENT_HOME" -xdev -type f \
        \( -name "id_rsa*" -o -name "id_ed25519*" -o -name ".git-credentials" \
           -o -name "*.token" -o -name "*.secret" -o -name "*.key" \) \
        -print -quit | grep -q .'
project_cmd exec "$INSTANCE" -- jq empty "$AGENT_HOME/.config/opencode/opencode.json"

assert_version \
    Node \
    "$NODE_EXPECTED_VERSION" \
    "$(guest_output node -p 'process.versions.node')"
# Compare the observed runtime with the evidence saved inside this image.
# shellcheck disable=SC2016
project_cmd exec "$INSTANCE" -- jq -e --arg node "$NODE_EXPECTED_VERSION" \
    '.toolchain.node == $node' /etc/vdm-opencode-platform/build.json >/dev/null

assert_version \
    OpenCode \
    "$OPENCODE_EXPECTED_VERSION" \
    "$(guest_output "$AGENT_HOME/.local/bin/opencode" --version | tr -d '[:space:]')"

assert_version \
    "Git MCP" \
    "$GIT_MCP_EXPECTED_VERSION" \
    "$(guest_output "$AGENT_HOME/.local/share/pipx/venvs/mcp-server-git/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("mcp-server-git"))' | tr -d '[:space:]')"

if image_has_component "$VARIANT" browser; then
    assert_version \
        Playwright \
        "$PLAYWRIGHT_EXPECTED_VERSION" \
        "$(guest_output playwright --version | awk '{print $2}')"
    assert_version \
        "Playwright MCP" \
        "$PLAYWRIGHT_MCP_EXPECTED_VERSION" \
        "$(guest_output npm list --global --json --depth=0 | jq -r '.dependencies["@playwright/mcp"].version')"
    project_cmd exec "$INSTANCE" -- test -x /usr/local/bin/vdm-playwright-mcp
    project_cmd exec "$INSTANCE" -- test -d /opt/ms-playwright
    # shellcheck disable=SC2016
    project_cmd exec "$INSTANCE" -- jq -e \
        '.mcp.playwright.enabled == true
         and .mcp.playwright.command[0] == "/usr/local/bin/vdm-playwright-mcp"' \
        "$AGENT_HOME/.config/opencode/opencode.json" >/dev/null
else
    project_cmd exec "$INSTANCE" -- test ! -x /usr/local/bin/vdm-playwright-mcp
    # shellcheck disable=SC2016
    project_cmd exec "$INSTANCE" -- jq -e \
        '.mcp.playwright.enabled == false' \
        "$AGENT_HOME/.config/opencode/opencode.json" >/dev/null
fi

# Native Joomla MCP is a remote service; no JavaScript Joomla server belongs in
# any language image. Every variant can configure a remote site when needed.
project_cmd exec "$INSTANCE" -- test -x /usr/local/libexec/vdm-joomla-mcp
project_cmd exec "$INSTANCE" -- test -x /usr/local/bin/vdm-joomla-mcp
project_cmd exec "$INSTANCE" -- test -x /usr/local/bin/vdm-joomla-mcp-config-check
project_cmd exec "$INSTANCE" -- test -r /etc/joomla-mcp/sites.readonly.example.json
project_cmd exec "$INSTANCE" -- test ! -e /etc/joomla-mcp/sites.json
project_cmd exec "$INSTANCE" -- test ! -e /usr/local/bin/vdm-joomla-mcp-http
project_cmd exec "$INSTANCE" -- test ! -e /usr/local/bin/vdm-joomla-mcp-live-test
guest_output npm list --global --json --depth=0 |
    jq -e '.dependencies["@joomengine/joomla-mcp"] == null' >/dev/null
# shellcheck disable=SC2016
project_cmd exec "$INSTANCE" -- jq -e \
    '.mcp.joomla.type == "remote"
     and .mcp.joomla.enabled == false
     and .mcp.joomla.url == "{env:JOOMLA_MCP_URL}"
     and .mcp.joomla.oauth == false
     and .mcp.joomla.headers["X-Joomla-Token"] == "{env:JOOMLA_MCP_SITE_TOKEN}"
     and ([.mcp | keys[] | select(startswith("joomla_"))] | length == 0)' \
    "$AGENT_HOME/.config/opencode/opencode.json" >/dev/null

if image_has_component "$VARIANT" typescript; then
    assert_version \
        TypeScript \
        "$TYPESCRIPT_EXPECTED_VERSION" \
        "$(guest_output tsc --version | awk 'NR == 1 {print $2}')"

    assert_version \
        TSX \
        "$TSX_EXPECTED_VERSION" \
        "$(
            guest_output tsx --version |
                awk 'NR == 1 {
                    version = $2
                    sub(/^v/, "", version)
                    print version
                }'
        )"
fi

if image_has_component "$VARIANT" python; then
    assert_version Ruff "$RUFF_EXPECTED_VERSION" "$(guest_output "$AGENT_HOME/.local/bin/ruff" --version | awk '{print $2}')"
    assert_version mypy "$MYPY_EXPECTED_VERSION" "$(guest_output "$AGENT_HOME/.local/bin/mypy" --version | awk '{print $2}')"
fi

log "Image verification passed for $VARIANT"
