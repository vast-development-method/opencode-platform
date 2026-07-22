#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

for command in incus jq tar zstd sha256sum; do
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

available_kib="$(df --output=avail -k "$ROOT_DIR" | awk 'NR == 2 {print $1}')"
required_kib="$((MIN_BUILD_FREE_GIB * 1024 * 1024))"
if [ "$available_kib" -lt "$required_kib" ]; then
    available_gib="$((available_kib / 1024 / 1024))"
    die "Insufficient build disk: ${available_gib} GiB available; ${MIN_BUILD_FREE_GIB} GiB required."
fi

log "Incus runner preflight passed"
