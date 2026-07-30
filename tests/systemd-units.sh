#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

command -v systemd-analyze >/dev/null 2>&1 || {
    printf 'systemd-analyze is required to validate host units.\n' >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
sed \
    -e '/^After=incus\.service$/d' \
    -e '/^Requires=incus\.service$/d' \
    -e 's|^ConditionFileIsExecutable=.*|ConditionFileIsExecutable=/bin/true|' \
    -e 's|^ExecStart=.*|ExecStart=/bin/true|' \
    "$ROOT_DIR/host/systemd/vdm-opencode-reaper.service.in" \
    > "$tmp_dir/vdm-opencode-reaper.service"
cp "$ROOT_DIR/host/systemd/vdm-opencode-reaper.timer" \
    "$tmp_dir/vdm-opencode-reaper.timer"

systemd-analyze verify \
    "$tmp_dir/vdm-opencode-reaper.service" \
    "$tmp_dir/vdm-opencode-reaper.timer"

printf 'Systemd unit validation passed.\n'
