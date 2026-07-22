#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

escaped_root="$(printf '%s' "$ROOT_DIR" | sed 's/[&|]/\\&/g')"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
sed "s|@ROOT_DIR@|$escaped_root|g" \
    "$ROOT_DIR/host/systemd/vdm-opencode-reaper.service.in" > "$tmp"
sudo install -o root -g root -m 0644 "$tmp" /etc/systemd/system/vdm-opencode-reaper.service
sudo install -o root -g root -m 0644 \
    "$ROOT_DIR/host/systemd/vdm-opencode-reaper.timer" \
    /etc/systemd/system/vdm-opencode-reaper.timer
sudo systemctl daemon-reload
sudo systemctl enable --now vdm-opencode-reaper.timer
log "Installed the agent VM expiry reaper"
