#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/runtime-credentials.sh"

NAME="${1:-}"
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ ]] ||
    die "Usage: $0 INSTANCE_NAME"

DIR="/run/user/${UID}/vdm-opencode"
FILE="${DIR}/${NAME}.env"
install -d -m 0700 "$DIR"
[ "$(stat -c '%u' "$DIR")" = "$UID" ] ||
    die "Runtime credential directory must be owned by UID $UID: $DIR"
umask 077

if [ -e "$FILE" ] || [ -L "$FILE" ]; then
    validate_runtime_file "$FILE"
else
    cat > "$FILE" <<'EOF'
# Runtime-only values. This directory is tmpfs and is removed at logout/reboot.
GITHUB_MCP_URL=
GITHUB_MCP_TOKEN=
GITEA_MCP_URL=
GITEA_MCP_TOKEN=
NEXTCLOUD_MCP_URL=
NEXTCLOUD_MCP_TOKEN=
STT_MCP_URL=
STT_MCP_TOKEN=
VDM_LOCAL_LLM_BASE_URL=http://10.248.18.1:11434/v1
VDM_LOCAL_LLM_MODEL=

# Local JoomEngine MCP for Joomla. Values are inherited only by the bounded session.
JOOMLA_MCP_SITE_TOKEN=
JOOMLA_MCP_APPROVAL_SECRET=
JOOMLA_MCP_UPDATE_TOKEN=
EOF
    chmod 0600 "$FILE"
fi

ensure_key() {
    local key="$1"
    grep -q "^${key}=" "$FILE" || printf '%s=\n' "$key" >> "$FILE"
}

# Upgrade existing per-instance files without changing any existing value.
ensure_key JOOMLA_MCP_SITE_TOKEN
ensure_key JOOMLA_MCP_APPROVAL_SECRET
ensure_key JOOMLA_MCP_UPDATE_TOKEN
chmod 0600 "$FILE"
validate_runtime_file "$FILE"

printf '%s\n' "$FILE"
