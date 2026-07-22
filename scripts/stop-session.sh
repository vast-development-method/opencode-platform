#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

NAME="${1:-}"
[ -n "$NAME" ] || die "Usage: $0 INSTANCE_NAME"

project_cmd exec "$NAME" -- bash -c \
    'systemctl list-units --type=service --all --no-legend "vdm-opencode-*.service" |
     awk "{print \$1}" | xargs -r systemctl stop' >/dev/null 2>&1 || true
project_cmd exec "$NAME" -- rm -rf /run/vdm-opencode-input /run/vdm-opencode-* >/dev/null 2>&1 || true
project_cmd config unset "$NAME" user.vdm.session.id >/dev/null 2>&1 || true
project_cmd config unset "$NAME" user.vdm.session.expires_epoch >/dev/null 2>&1 || true
project_cmd stop "$NAME" --timeout 60
