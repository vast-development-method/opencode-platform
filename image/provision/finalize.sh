#!/usr/bin/env bash
set -Eeuo pipefail

VARIANT="${1:?variant required}"
PLATFORM_VERSION="${PLATFORM_VERSION:?platform version required}"
AGENT_USER="${AGENT_USER:-opencode}"
AGENT_HOME="/home/${AGENT_USER}"

install -d -m 0755 /etc/vdm-opencode-platform

jq -n \
  --arg platform "vdm-opencode-platform" \
  --arg version "$PLATFORM_VERSION" \
  --arg variant "$VARIANT" \
  --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg os "$(. /etc/os-release && printf '%s %s' "$ID" "$VERSION_ID")" \
  --arg opencode "$(sudo -u "$AGENT_USER" -H "$AGENT_HOME/.local/bin/opencode" --version 2>/dev/null || true)" \
  --arg node "$(node --version 2>/dev/null || true)" \
  --arg php "$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)" \
  --arg python "$(python3 --version 2>/dev/null || true)" \
  '{
    platform: $platform,
    version: $version,
    variant: $variant,
    built_at: $built_at,
    os: $os,
    toolchain: {
      opencode: $opencode,
      node: $node,
      php: $php,
      python: $python
    }
  }' > /etc/vdm-opencode-platform/build.json

rm -rf \
  /root/.cache \
  /root/.npm \
  /root/.local/share/opencode \
  "$AGENT_HOME/.cache" \
  "$AGENT_HOME/.npm" \
  "$AGENT_HOME/.local/share/opencode/auth.json" \
  "$AGENT_HOME/.local/share/opencode/mcp-auth.json" \
  "$AGENT_HOME/.ssh/id_rsa" \
  "$AGENT_HOME/.ssh/id_ed25519" \
  "$AGENT_HOME/.bash_history"

find "$AGENT_HOME" -type f \( -name '*.token' -o -name '*.secret' -o -name '.git-credentials' \) -delete
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME" /workspace
