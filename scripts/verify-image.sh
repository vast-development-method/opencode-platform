#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

INSTANCE="${1:?instance required}"
VARIANT="${2:?variant required}"

project_cmd exec "$INSTANCE" -- test -x "/home/$AGENT_USER/.local/bin/opencode"
project_cmd exec "$INSTANCE" -- test -f /etc/opencode/opencode.json
project_cmd exec "$INSTANCE" -- test -f /etc/vdm-opencode-platform/build.json
project_cmd exec "$INSTANCE" -- jq -e --arg variant "$VARIANT" '.variant == $variant' /etc/vdm-opencode-platform/build.json >/dev/null
project_cmd exec "$INSTANCE" -- test ! -e "/home/$AGENT_USER/.local/share/opencode/auth.json"
project_cmd exec "$INSTANCE" -- test ! -e "/home/$AGENT_USER/.local/share/opencode/mcp-auth.json"
project_cmd exec "$INSTANCE" -- bash -c \
    '! find /home/opencode -xdev -type f \( -name "id_rsa*" -o -name "id_ed25519*" -o -name ".git-credentials" \) -print -quit | grep -q .'

if [ "$VARIANT" = php ] || [ "$VARIANT" = typescript ] || [ "$VARIANT" = full ]; then
    project_cmd exec "$INSTANCE" -- node --version
    project_cmd exec "$INSTANCE" -- npx playwright --version
fi

log "Image verification passed for $VARIANT"
