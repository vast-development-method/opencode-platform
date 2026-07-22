#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

VARIANT="${1:-}"
OUTPUT_DIR="${2:-$ROOT_DIR/build/packages/${PLATFORM_VERSION}/${VARIANT}}"
variant_exists "$VARIANT" || die "Unknown variant: $VARIANT"
ALIAS="$(image_alias "$VARIANT")"

install -d -m 0750 "$OUTPUT_DIR"
find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
project_cmd image export "$ALIAS" "$OUTPUT_DIR/${INCUS_IMAGE_PREFIX}-${VARIANT}-${PLATFORM_VERSION}"

source_revision="unknown"
if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    source_revision="$(git -C "$ROOT_DIR" rev-parse HEAD)"
fi

payload_json="$(
    find "$OUTPUT_DIR" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort | while IFS= read -r name; do
        jq -n \
            --arg name "$name" \
            --arg sha256 "$(sha256sum "$OUTPUT_DIR/$name" | awk '{print $1}')" \
            --argjson bytes "$(stat -c '%s' "$OUTPUT_DIR/$name")" \
            '{name:$name,sha256:$sha256,bytes:$bytes}'
    done | jq -s .
)"

jq -n \
  --argjson schema 1 \
  --arg platform "$PLATFORM_NAME" \
  --arg version "$PLATFORM_VERSION" \
  --arg variant "$VARIANT" \
  --arg image "$ALIAS" \
  --arg architecture "$(uname -m)" \
  --arg source_revision "$source_revision" \
  --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson payload "$payload_json" \
  '{
    schema:$schema,
    platform:$platform,
    version:$version,
    variant:$variant,
    image:$image,
    architecture:$architecture,
    source_revision:$source_revision,
    packaged_at:$built_at,
    payload:$payload
  }' \
  > "$OUTPUT_DIR/manifest.json"

checksums_file="$(mktemp)"
trap 'rm -f "$checksums_file"' EXIT
(
    cd "$OUTPUT_DIR"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\0' \
        | LC_ALL=C sort -z \
        | xargs -0 sha256sum > "$checksums_file"
)
install -m 0640 "$checksums_file" "$OUTPUT_DIR/SHA256SUMS"

log "Packaged image in $OUTPUT_DIR"
