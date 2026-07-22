#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
for variant in "${PLATFORM_RELEASE_IMAGES[@]}"; do
    "$SCRIPT_DIR/build-image.sh" "$variant"
done
