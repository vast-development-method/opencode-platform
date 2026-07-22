#!/usr/bin/env bash
set -Eeuo pipefail
PACKAGE_DIR="${1:?package directory required}"
[ -f "$PACKAGE_DIR/manifest.json" ] || { printf 'manifest.json is missing\n' >&2; exit 1; }
[ -f "$PACKAGE_DIR/SHA256SUMS" ] || { printf 'SHA256SUMS is missing\n' >&2; exit 1; }
(
    cd "$PACKAGE_DIR"
    sha256sum --check --strict SHA256SUMS
)
jq -e '
  .schema == 2 and
  (.artifact_id | type == "string") and
  .platform == "vdm-opencode-platform" and
  (.version | type == "string") and
  (.variant | type == "string") and
  (.architecture == "amd64" or .architecture == "arm64") and
  (.payload | type == "array" and length > 0)
' "$PACKAGE_DIR/manifest.json" >/dev/null
if [ -f "$PACKAGE_DIR/SHA256SUMS.sigstore.json" ]; then
    : "${COSIGN_PUBLIC_KEY:?COSIGN_PUBLIC_KEY is required to verify a signed artifact}"
    cosign verify-blob \
        --key "$COSIGN_PUBLIC_KEY" \
        --bundle "$PACKAGE_DIR/SHA256SUMS.sigstore.json" \
        "$PACKAGE_DIR/SHA256SUMS"
fi
