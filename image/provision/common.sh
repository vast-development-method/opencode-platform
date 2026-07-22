#!/usr/bin/env bash
set -Eeuo pipefail

AGENT_USER="${AGENT_USER:-opencode}"
AGENT_HOME="/home/${AGENT_USER}"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    bash-completion \
    build-essential \
    ca-certificates \
    curl \
    fd-find \
    git \
    gnupg \
    jq \
    locales \
    openssh-client \
    pipx \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    rsync \
    shellcheck \
    sudo \
    tmux \
    unzip \
    xz-utils \
    zip

if ! id "$AGENT_USER" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "$AGENT_USER"
fi

install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 0750 /workspace
install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 0750 "$AGENT_HOME/.local/bin"
install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 0750 "$AGENT_HOME/.config/opencode/agents"
install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 0700 "$AGENT_HOME/.local/share/opencode"
install -d -m 0755 /etc/opencode /etc/vdm-opencode-platform

if ! command -v node >/dev/null 2>&1 || [ "$(node --version | sed 's/^v//' | cut -d. -f1)" -lt 20 ]; then
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR:-22}.x" | bash -
    apt-get install -y --no-install-recommends nodejs
fi

if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
fi

npm install --global "${OPENCODE_PACKAGE:?OPENCODE_PACKAGE is required}"
opencode_path="$(command -v opencode)"
ln -sfn "$opencode_path" "$AGENT_HOME/.local/bin/opencode"

sudo -u "$AGENT_USER" -H env \
    UV_TOOL_BIN_DIR="$AGENT_HOME/.local/bin" \
    UV_TOOL_DIR="$AGENT_HOME/.local/share/uv/tools" \
    uv tool install --force "${GIT_MCP_PACKAGE:?GIT_MCP_PACKAGE is required}"

test -x "$AGENT_HOME/.local/bin/opencode"
test -x "$AGENT_HOME/.local/bin/mcp-server-git"

installed_opencode="$("$AGENT_HOME/.local/bin/opencode" --version | tr -d '[:space:]')"
[ "$installed_opencode" = "$OPENCODE_EXPECTED_VERSION" ] || {
    printf 'OpenCode version mismatch: expected %s, got %s\n' \
        "$OPENCODE_EXPECTED_VERSION" "$installed_opencode" >&2
    exit 1
}

installed_git_mcp="$(sudo -u "$AGENT_USER" -H \
    "$AGENT_HOME/.local/share/uv/tools/mcp-server-git/bin/python" -c \
    'import importlib.metadata; print(importlib.metadata.version("mcp-server-git"))')"
[ "$installed_git_mcp" = "$GIT_MCP_EXPECTED_VERSION" ] || {
    printf 'Git MCP version mismatch: expected %s, got %s\n' \
        "$GIT_MCP_EXPECTED_VERSION" "$installed_git_mcp" >&2
    exit 1
}

git config --system init.defaultBranch main
git config --system fetch.prune true
git config --system pull.ff only
git config --system credential.helper ""

ln -sf /usr/bin/fdfind /usr/local/bin/fd
chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME"
