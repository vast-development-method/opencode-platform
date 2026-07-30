#!/usr/bin/env bash
set -Eeuo pipefail

AGENT_USER="${AGENT_USER:-opencode}"
AGENT_HOME="${AGENT_HOME:-/home/${AGENT_USER}}"
BUILD_CACHE_DIR="${VDM_BUILD_CACHE_DIR:-}"
export DEBIAN_FRONTEND=noninteractive

[[ "$AGENT_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || {
    printf 'Unsafe agent user: %s\n' "$AGENT_USER" >&2
    exit 1
}
if [[ ! "$AGENT_HOME" =~ ^/(home|srv)/[A-Za-z0-9._/-]+$ ]] ||
    [[ "/${AGENT_HOME#/}/" == *'/../'* ]] ||
    [[ "/${AGENT_HOME#/}/" == *'/./'* ]] ||
    [[ "$AGENT_HOME" == *'//'* ]]; then
    printf 'Unsafe agent home: %s\n' "$AGENT_HOME" >&2
    exit 1
fi

if [ -n "$BUILD_CACHE_DIR" ]; then
    install -d -m 0755 \
        "$BUILD_CACHE_DIR/apt/archives/partial" \
        "$BUILD_CACHE_DIR/npm" \
        "$BUILD_CACHE_DIR/pip"
    cat > /etc/apt/apt.conf.d/90-vdm-build-cache <<EOF
Dir::Cache::archives "$BUILD_CACHE_DIR/apt/archives";
EOF
fi

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
    useradd --create-home --home-dir "$AGENT_HOME" --shell /bin/bash "$AGENT_USER"
else
    account_home="$(getent passwd "$AGENT_USER" | cut -d: -f6)"
    [ "$account_home" = "$AGENT_HOME" ] || {
        printf 'Existing user %s has home %s, expected %s\n' \
            "$AGENT_USER" "$account_home" "$AGENT_HOME" >&2
        exit 1
    }
fi

template_home=/home/opencode
if [ "$AGENT_HOME" != "$template_home" ] && [ -d "$template_home" ]; then
    [[ "$AGENT_HOME" != "$template_home/"* ]] || {
        printf 'Agent home cannot be nested below the template home: %s\n' "$AGENT_HOME" >&2
        exit 1
    }
    cp -a "$template_home/." "$AGENT_HOME/"
    rm -rf "$template_home"
fi
if [ -n "$BUILD_CACHE_DIR" ]; then
    chown -R "$AGENT_USER:$AGENT_USER" \
        "$BUILD_CACHE_DIR/npm" \
        "$BUILD_CACHE_DIR/pip"
fi

install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 0750 /workspace
install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 0750 "$AGENT_HOME/.local/bin"
install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 0750 "$AGENT_HOME/.config/opencode/agents"
install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 0700 "$AGENT_HOME/.local/share/opencode"
install -d -m 0755 /etc/opencode /etc/vdm-opencode-platform

config="$AGENT_HOME/.config/opencode/opencode.json"
tmp="$(mktemp)"
jq --arg agent_home "$AGENT_HOME" \
    '.mcp.git.command[0] = ($agent_home + "/.local/bin/mcp-server-git")' \
    "$config" > "$tmp"
install -o "$AGENT_USER" -g "$AGENT_USER" -m 0640 "$tmp" "$config"
rm -f "$tmp"

if ! command -v node >/dev/null 2>&1 || [ "$(node --version | sed 's/^v//' | cut -d. -f1)" -lt 20 ]; then
    nodesource_setup="$(mktemp)"
    trap 'rm -f "$nodesource_setup"' EXIT
    curl --fail --silent --show-error --location \
        "https://deb.nodesource.com/setup_${NODE_MAJOR:-22}.x" \
        --output "$nodesource_setup"
    printf '%s  %s\n' \
        "${NODESOURCE_SETUP_SHA256:?NODESOURCE_SETUP_SHA256 is required}" \
        "$nodesource_setup" | sha256sum --check --strict
    bash "$nodesource_setup"
    rm -f "$nodesource_setup"
    trap - EXIT
    apt-get install -y --no-install-recommends nodejs
fi

npm install --global "${OPENCODE_PACKAGE:?OPENCODE_PACKAGE is required}"
opencode_path="$(command -v opencode)"
ln -sfn "$opencode_path" "$AGENT_HOME/.local/bin/opencode"

sudo -u "$AGENT_USER" -H env \
    PIPX_HOME="$AGENT_HOME/.local/share/pipx" \
    PIPX_BIN_DIR="$AGENT_HOME/.local/bin" \
    PIP_CACHE_DIR="${PIP_CACHE_DIR:-$AGENT_HOME/.cache/pip}" \
    pipx install --force "${GIT_MCP_PACKAGE:?GIT_MCP_PACKAGE is required}"

test -x "$AGENT_HOME/.local/bin/opencode"
test -x "$AGENT_HOME/.local/bin/mcp-server-git"

installed_opencode="$("$AGENT_HOME/.local/bin/opencode" --version | tr -d '[:space:]')"
[ "$installed_opencode" = "$OPENCODE_EXPECTED_VERSION" ] || {
    printf 'OpenCode version mismatch: expected %s, got %s\n' \
        "$OPENCODE_EXPECTED_VERSION" "$installed_opencode" >&2
    exit 1
}

installed_git_mcp="$(sudo -u "$AGENT_USER" -H \
    "$AGENT_HOME/.local/share/pipx/venvs/mcp-server-git/bin/python" -c \
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
