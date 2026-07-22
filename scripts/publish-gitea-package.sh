#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

VARIANT="${1:-}"
PACKAGE_DIR="${2:-$ROOT_DIR/build/packages/${PLATFORM_VERSION}/${VARIANT}}"
variant_exists "$VARIANT" || die "Unknown variant: $VARIANT"
[ -d "$PACKAGE_DIR" ] || die "Package directory missing: $PACKAGE_DIR"

: "${GITEA_PACKAGE_OWNER:?Set GITEA_PACKAGE_OWNER}"
: "${GITEA_PACKAGE_TOKEN:?Set GITEA_PACKAGE_TOKEN in the CI runtime only}"
GITEA_PACKAGE_USER="${GITEA_PACKAGE_USER:-package-publisher}"
PACKAGE_NAME="${GITEA_PACKAGE_NAME:-vdm-opencode-${VARIANT}}"

for file in "$PACKAGE_DIR"/*; do
    [ -f "$file" ] || continue
    name="$(basename "$file")"
    curl --fail-with-body \
        --user "${GITEA_PACKAGE_USER}:${GITEA_PACKAGE_TOKEN}" \
        --upload-file "$file" \
        "${GITEA_BASE_URL}/api/packages/${GITEA_PACKAGE_OWNER}/generic/${PACKAGE_NAME}/${PLATFORM_VERSION}/${name}"
done

log "Published ${PACKAGE_NAME}/${PLATFORM_VERSION}"
