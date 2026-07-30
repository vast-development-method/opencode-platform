#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

NAME="${1:-}"
[ -n "$NAME" ] || die "Usage: $0 INSTANCE_NAME"

stop_guest_sessions "$NAME"
cleanup_guest_runtime "$NAME"
project_cmd config unset "$NAME" user.vdm.session.id >/dev/null 2>&1 || true
project_cmd config unset "$NAME" user.vdm.session.expires_epoch >/dev/null 2>&1 || true
project_cmd stop "$NAME" --timeout 60
