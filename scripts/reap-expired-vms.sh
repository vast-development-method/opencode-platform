#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

NOW="${VDM_REAPER_NOW:-$(date +%s)}"
[[ "$NOW" =~ ^[0-9]+$ ]] || die "VDM_REAPER_NOW must be an epoch integer"

mapfile -t rows < <(
    project_cmd list --format json |
        jq -r '.[] | select(.status == "Running") |
            [.name, (.config["user.vdm.session.expires_epoch"] // "")] | @tsv'
)

for row in "${rows[@]}"; do
    IFS=$'\t' read -r name expires <<< "$row"
    [ -n "$expires" ] || continue
    if [[ ! "$expires" =~ ^[0-9]+$ ]]; then
        warn "Ignoring malformed expiry metadata on $name: $expires"
        continue
    fi
    if ((expires <= NOW)); then
        log "Stopping expired agent VM $name"
        stop_guest_sessions "$name"
        cleanup_guest_runtime "$name"
        project_cmd stop "$name" --timeout 30 >/dev/null 2>&1 || project_cmd stop "$name" --force
        project_cmd config unset "$name" user.vdm.session.id >/dev/null 2>&1 || true
        project_cmd config unset "$name" user.vdm.session.expires_epoch >/dev/null 2>&1 || true
    fi
done
