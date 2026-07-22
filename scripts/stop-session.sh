#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

NAME="${1:-}"
[ -n "$NAME" ] || die "Usage: $0 INSTANCE_NAME"

project_cmd exec "$NAME" -- pkill -u "$AGENT_USER" -x opencode >/dev/null 2>&1 || true
project_cmd exec "$NAME" -- rm -rf /run/vdm-opencode-session >/dev/null 2>&1 || true
project_cmd stop "$NAME" --timeout 60
