#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

VARIANT="${1:-}"
OUTPUT_DIR="${2:-$ROOT_DIR/build/packages/${PLATFORM_VERSION}/${VARIANT}}"
variant_exists "$VARIANT" || die "Unknown variant: $VARIANT"
ALIAS="$(image_alias "$VARIANT")"

rm -rf "$OUTPUT_DIR"
install -d -m 0750 "$OUTPUT_DIR"
project_cmd image export "$ALIAS" "$OUTPUT_DIR/${INCUS_IMAGE_PREFIX}-${VARIANT}-${PLATFORM_VERSION}"

(
    cd "$OUTPUT_DIR"
    sha256sum ./* > SHA256SUMS
)

jq -n \
  --arg platform "$PLATFORM_NAME" \
  --arg version "$PLATFORM_VERSION" \
  --arg variant "$VARIANT" \
  --arg image "$ALIAS" \
  '{platform:$platform,version:$version,variant:$variant,image:$image}' \
  > "$OUTPUT_DIR/manifest.json"

log "Packaged image in $OUTPUT_DIR"
