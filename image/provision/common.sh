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

sudo -u "$AGENT_USER" -H env OPENCODE_INSTALL_DIR="$AGENT_HOME/.local/bin" \
    bash -c 'curl -fsSL "${OPENCODE_INSTALL_URL:-https://opencode.ai/install}" | bash'

test -x "$AGENT_HOME/.local/bin/opencode"

git config --system init.defaultBranch main
git config --system fetch.prune true
git config --system pull.ff only
git config --system credential.helper ""

ln -sf /usr/bin/fdfind /usr/local/bin/fd
chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME"
