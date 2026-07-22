#!/usr/bin/env bash
set -Eeuo pipefail

NAME="${1:-}"
[ -n "$NAME" ] || {
    printf 'Usage: %s INSTANCE_NAME\n' "$0" >&2
    exit 1
}

DIR="/run/user/${UID}/vdm-opencode"
FILE="${DIR}/${NAME}.env"
install -d -m 0700 "$DIR"
umask 077

if [ ! -f "$FILE" ]; then
    cat > "$FILE" <<'EOF'
# Runtime-only values. This directory is tmpfs and is removed at logout/reboot.
GITHUB_MCP_URL=
GITHUB_MCP_TOKEN=
GITEA_MCP_URL=
GITEA_MCP_TOKEN=
NEXTCLOUD_MCP_URL=
NEXTCLOUD_MCP_TOKEN=
JOOMLA_MCP_URL=
JOOMLA_MCP_TOKEN=
JCB_MCP_URL=
JCB_MCP_TOKEN=
STT_MCP_URL=
STT_MCP_TOKEN=
VDM_LOCAL_LLM_BASE_URL=http://10.248.18.1:11434/v1
VDM_LOCAL_LLM_MODEL=
EOF
    chmod 0600 "$FILE"
fi

printf '%s\n' "$FILE"
