#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for variant in base php python cpp typescript full; do
    "$SCRIPT_DIR/build-image.sh" "$variant"
done
