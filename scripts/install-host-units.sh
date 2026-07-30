#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

for command in install sudo systemctl systemd-analyze; do
    require_command "$command"
done

RUNTIME_ROOT=/usr/local/libexec/vdm-opencode
CONFIG_ROOT=/etc/vdm-opencode-platform
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

[[ "$INCUS_PROJECT" =~ ^[A-Za-z0-9_.-]+$ ]] ||
    die "Unsafe Incus project name: $INCUS_PROJECT"
printf 'INCUS_PROJECT=%s\n' "$INCUS_PROJECT" > "$tmp_dir/reaper.env"

sudo systemctl stop \
    vdm-opencode-reaper.timer \
    vdm-opencode-reaper.service >/dev/null 2>&1 ||
    true
sudo install -d -o root -g root -m 0755 \
    "$RUNTIME_ROOT/scripts/lib" \
    "$RUNTIME_ROOT/manifest/generated" \
    "$CONFIG_ROOT"
sudo install -o root -g root -m 0755 \
    "$ROOT_DIR/scripts/reap-expired-vms.sh" \
    "$RUNTIME_ROOT/scripts/reap-expired-vms.sh"
sudo install -o root -g root -m 0644 \
    "$ROOT_DIR/scripts/lib/common.sh" \
    "$RUNTIME_ROOT/scripts/lib/common.sh"
sudo install -o root -g root -m 0644 \
    "$ROOT_DIR/manifest/generated/platform.env" \
    "$RUNTIME_ROOT/manifest/generated/platform.env"
sudo install -o root -g root -m 0644 \
    "$ROOT_DIR/manifest/platform.env" \
    "$ROOT_DIR/manifest/toolchain.env" \
    "$RUNTIME_ROOT/manifest/"
sudo install -o root -g root -m 0644 \
    "$tmp_dir/reaper.env" \
    "$CONFIG_ROOT/reaper.env"
sudo install -o root -g root -m 0644 \
    "$ROOT_DIR/host/systemd/vdm-opencode-reaper.service.in" \
    /etc/systemd/system/vdm-opencode-reaper.service
sudo install -o root -g root -m 0644 \
    "$ROOT_DIR/host/systemd/vdm-opencode-reaper.timer" \
    /etc/systemd/system/vdm-opencode-reaper.timer
sudo systemd-analyze verify \
    /etc/systemd/system/vdm-opencode-reaper.service \
    /etc/systemd/system/vdm-opencode-reaper.timer
sudo systemctl daemon-reload
sudo systemctl enable --now vdm-opencode-reaper.timer
log "Installed the root-owned agent VM expiry reaper runtime"
