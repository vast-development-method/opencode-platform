#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

VARIANT="${1:-}"
NAME="${2:-}"
variant_exists "$VARIANT" || die "Variant must be one of: base php python cpp typescript full"
[ -n "$NAME" ] || die "Usage: $0 VARIANT INSTANCE_NAME"

ALIAS="$(image_alias "$VARIANT")"
project_cmd image show "$ALIAS" >/dev/null 2>&1 || die "Image not found: $ALIAS. Build or import it first."
project_cmd info "$NAME" >/dev/null 2>&1 && die "Instance already exists: $NAME"

project_cmd init "$ALIAS" "$NAME" --vm --profile "vdm-opencode-${VARIANT}"
project_cmd start "$NAME"
wait_for_vm "$NAME" || die "VM agent did not become ready: $NAME"
project_cmd snapshot create "$NAME" factory
log "Launched $NAME from $ALIAS"
