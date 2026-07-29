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

RUNTIME_BASE="${VDM_RUNTIME_BASE:-/run/user/${UID}}"
[[ "$RUNTIME_BASE" == /* && "$RUNTIME_BASE" != *$'\n'* ]] ||
    die "VDM_RUNTIME_BASE must be an absolute path without newlines"
[ ! -L "$RUNTIME_BASE" ] ||
    die "Runtime base must not be a symbolic link: $RUNTIME_BASE"
if [ -e "$RUNTIME_BASE" ]; then
    [ -d "$RUNTIME_BASE" ] ||
        die "Runtime base must be a directory: $RUNTIME_BASE"
else
    runtime_parent="$(dirname "$RUNTIME_BASE")"
    [ -d "$runtime_parent" ] ||
        die "Runtime base parent does not exist: $runtime_parent"
    [ "$(stat -f -c '%T' "$runtime_parent")" = tmpfs ] ||
        die "Runtime base parent must be backed by tmpfs: $runtime_parent"
    install -d -m 0700 "$RUNTIME_BASE"
fi
[ "$(stat -c '%u' "$RUNTIME_BASE")" = "$UID" ] ||
    die "Runtime base must be owned by UID $UID: $RUNTIME_BASE"
[ "$(stat -c '%a' "$RUNTIME_BASE")" = 700 ] ||
    die "Runtime base must have mode 0700: $RUNTIME_BASE"
[ "$(stat -f -c '%T' "$RUNTIME_BASE")" = tmpfs ] ||
    die "Runtime base must be backed by tmpfs: $RUNTIME_BASE"

DIR="${RUNTIME_BASE}/vdm-opencode"
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
