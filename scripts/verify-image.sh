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

project_cmd exec "$INSTANCE" -- test -x "/home/$AGENT_USER/.local/bin/opencode"
project_cmd exec "$INSTANCE" -- test -f /etc/opencode/opencode.json
project_cmd exec "$INSTANCE" -- test -f /etc/vdm-opencode-platform/build.json
# The jq program must reach the guest unchanged.
# shellcheck disable=SC2016
project_cmd exec "$INSTANCE" -- jq -e --arg variant "$VARIANT" '.variant == $variant' /etc/vdm-opencode-platform/build.json >/dev/null
project_cmd exec "$INSTANCE" -- test ! -e "/home/$AGENT_USER/.local/share/opencode/auth.json"
project_cmd exec "$INSTANCE" -- test ! -e "/home/$AGENT_USER/.local/share/opencode/mcp-auth.json"
project_cmd exec "$INSTANCE" -- test ! -e /opt/vdm-build
project_cmd exec "$INSTANCE" -- test ! -s /etc/machine-id
project_cmd exec "$INSTANCE" -- bash -c '! compgen -G "/etc/ssh/ssh_host_*" >/dev/null'
project_cmd exec "$INSTANCE" -- bash -c \
    '! find /home/opencode -xdev -type f \( -name "id_rsa*" -o -name "id_ed25519*" -o -name ".git-credentials" \) -print -quit | grep -q .'

assert_version \
    OpenCode \
    "$OPENCODE_EXPECTED_VERSION" \
    "$(guest_output "/home/$AGENT_USER/.local/bin/opencode" --version | tr -d '[:space:]')"

assert_version \
    "Git MCP" \
    "$GIT_MCP_EXPECTED_VERSION" \
    "$(guest_output "/home/$AGENT_USER/.local/share/pipx/venvs/mcp-server-git/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("mcp-server-git"))' | tr -d '[:space:]')"

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
fi

if image_has_component "$VARIANT" typescript; then
    assert_version TypeScript "$TYPESCRIPT_EXPECTED_VERSION" "$(guest_output tsc --version | awk '{print $2}')"
    assert_version TSX "$TSX_EXPECTED_VERSION" "$(guest_output tsx --version | awk 'NR == 1 {print $2}')"
fi

if image_has_component "$VARIANT" python; then
    assert_version Ruff "$RUFF_EXPECTED_VERSION" "$(guest_output "/home/$AGENT_USER/.local/bin/ruff" --version | awk '{print $2}')"
    assert_version mypy "$MYPY_EXPECTED_VERSION" "$(guest_output "/home/$AGENT_USER/.local/bin/mypy" --version | awk '{print $2}')"
fi

log "Image verification passed for $VARIANT"
