#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/build-resources.sh"

VARIANT="${1:-}"
if [ -n "$VARIANT" ]; then
    variant_exists "$VARIANT" ||
        die "Runner preflight variant must be one of: ${PLATFORM_IMAGES[*]}"
fi

for command in incus jq tar zstd sha256sum getconf; do
    require_command "$command"
done

[ "$(uname -s)" = Linux ] || die "The image runner must be Linux."
if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    die "The image runner requires read/write access to /dev/kvm."
fi

incus_cmd info >/dev/null 2>&1 || die "The runner cannot communicate with the Incus daemon."

storage_pool="${INCUS_STORAGE_POOL:-default}"
incus_cmd storage show "$storage_pool" >/dev/null 2>&1 || \
    die "Incus storage pool not found: $storage_pool"

server_version="$(
    incus_cmd version |
        awk -F': ' '/^Server version:/ {print $2; exit}'
)"
[ -n "$server_version" ] || die "Unable to determine the Incus server version."
version_at_least "$server_version" "$MIN_INCUS_VERSION" ||
    die "Incus $server_version is older than the supported minimum $MIN_INCUS_VERSION."

if [ -n "$VARIANT" ]; then
    cache_value="${VDM_BUILD_CACHE:-true}"
    case "${cache_value,,}" in
        true|1|yes) cache_enabled=true ;;
        false|0|no) cache_enabled=false ;;
        *) die "VDM_BUILD_CACHE must be true or false." ;;
    esac
    select_build_resources "$VARIANT" "$storage_pool" "$cache_enabled"
    print_build_resource_plan "$VARIANT"
fi

log "Incus runner preflight passed${VARIANT:+ for $VARIANT}"
