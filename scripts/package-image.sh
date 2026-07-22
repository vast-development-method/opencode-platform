#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

VARIANT="${1:-}"
ARCHITECTURE="$(canonical_architecture "${VDM_BUILD_ARCHITECTURE:-}")"
OUTPUT_DIR="${2:-$ROOT_DIR/build/packages/${PLATFORM_VERSION}/${ARCHITECTURE}/${VARIANT}}"
variant_exists "$VARIANT" || die "Unknown variant: $VARIANT"
ALIAS="$(image_alias "$VARIANT" "$ARCHITECTURE")"
ARTIFACT_ID="$(artifact_id "$VARIANT" "$ARCHITECTURE")"

install -d -m 0750 "$OUTPUT_DIR"
find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
install -d -m 0750 "$OUTPUT_DIR/payload" "$OUTPUT_DIR/evidence"
project_cmd image export "$ALIAS" "$OUTPUT_DIR/payload/$ARTIFACT_ID"

source_revision="unknown"
source_tag=""
if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    source_revision="$(git -C "$ROOT_DIR" rev-parse HEAD)"
    source_tag="$(git -C "$ROOT_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)"
fi

payload_json="$(
    find "$OUTPUT_DIR/payload" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort | while IFS= read -r name; do
        jq -n \
            --arg name "payload/$name" \
            --arg sha256 "$(sha256sum "$OUTPUT_DIR/payload/$name" | awk '{print $1}')" \
            --argjson bytes "$(stat -c '%s' "$OUTPUT_DIR/payload/$name")" \
            '{name:$name,sha256:$sha256,bytes:$bytes}'
    done | jq -s .
)"

jq -n \
    --argjson schema 2 \
    --arg artifact_id "$ARTIFACT_ID" \
    --arg platform "$PLATFORM_NAME" \
    --arg version "$PLATFORM_VERSION" \
    --arg variant "$VARIANT" \
    --arg image "$ALIAS" \
    --arg architecture "$ARCHITECTURE" \
    --arg incus_architecture "$(uname -m)" \
    --arg source_revision "$source_revision" \
    --arg source_tag "$source_tag" \
    --arg packaged_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson payload "$payload_json" \
    '{
      schema:$schema,
      artifact_id:$artifact_id,
      platform:$platform,
      version:$version,
      variant:$variant,
      image:$image,
      architecture:$architecture,
      incus_architecture:$incus_architecture,
      source_revision:$source_revision,
      source_tag:$source_tag,
      packaged_at:$packaged_at,
      payload:$payload,
      supply_chain:{sbom:"not-generated",vulnerability_scan:"not-generated",signature:"not-generated"}
    }' > "$OUTPUT_DIR/manifest.json"

if command -v syft >/dev/null 2>&1; then
    "$SCRIPT_DIR/generate-sbom.sh" "$OUTPUT_DIR"
    tmp="$(mktemp)"
    jq '.supply_chain.sbom = "sbom.spdx.json"' "$OUTPUT_DIR/manifest.json" > "$tmp"
    install -m 0640 "$tmp" "$OUTPUT_DIR/manifest.json"
    rm -f "$tmp"
elif [ "${VDM_RELEASE_MODE:-false}" = true ]; then
    die "syft is required in release mode"
fi

if [ -f "$OUTPUT_DIR/sbom.spdx.json" ] && command -v grype >/dev/null 2>&1; then
    "$SCRIPT_DIR/scan-sbom.sh" "$OUTPUT_DIR"
    tmp="$(mktemp)"
    jq '.supply_chain.vulnerability_scan = "vulnerabilities.grype.json"' "$OUTPUT_DIR/manifest.json" > "$tmp"
    install -m 0640 "$tmp" "$OUTPUT_DIR/manifest.json"
    rm -f "$tmp"
elif [ "${VDM_RELEASE_MODE:-false}" = true ]; then
    die "grype and a generated SBOM are required in release mode"
fi

"$SCRIPT_DIR/generate-provenance.sh" "$OUTPUT_DIR"

if [ -n "${COSIGN_KEY:-}" ]; then
    tmp="$(mktemp)"
    jq '.supply_chain.signature = "SHA256SUMS.sigstore.json"' "$OUTPUT_DIR/manifest.json" > "$tmp"
    install -m 0640 "$tmp" "$OUTPUT_DIR/manifest.json"
    rm -f "$tmp"
fi

(
    cd "$OUTPUT_DIR"
    find . -type f \
        ! -name SHA256SUMS \
        ! -name SHA256SUMS.sigstore.json \
        -printf '%P\0' |
        LC_ALL=C sort -z |
        xargs -0 sha256sum > SHA256SUMS
)
chmod 0640 "$OUTPUT_DIR/SHA256SUMS"

if [ -n "${COSIGN_KEY:-}" ]; then
    "$SCRIPT_DIR/sign-artifact.sh" "$OUTPUT_DIR"
elif [ "${VDM_RELEASE_MODE:-false}" = true ]; then
    die "COSIGN_KEY (normally openbao://vdm-opencode-release) is required in release mode"
fi

"$SCRIPT_DIR/verify-artifact.sh" "$OUTPUT_DIR"
log "Packaged $ARTIFACT_ID in $OUTPUT_DIR"
