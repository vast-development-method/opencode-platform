#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export PATH="$ROOT_DIR/tests/fixtures:$PATH"
export MOCK_INCUS_LOG="$tmp_dir/incus.log"
output_dir="$tmp_dir/package"
platform_version="$(<"$ROOT_DIR/VERSION")"
artifact_id="vdm-opencode-base-${platform_version}-amd64"

"$ROOT_DIR/scripts/package-image.sh" base "$output_dir"

jq -e \
    --arg version "$platform_version" \
    --arg artifact_id "$artifact_id" \
    '
        .schema == 2 and
        .platform == "vdm-opencode-platform" and
        .version == $version and
        .variant == "base" and
        .architecture == "amd64" and
        .artifact_id == $artifact_id and
        (.payload | length == 2)
    ' "$output_dir/manifest.json" >/dev/null

(
    cd "$output_dir"
    sha256sum --check --strict SHA256SUMS
)

"$ROOT_DIR/scripts/import-image-package.sh" "$output_dir" "vdm-opencode-base/test"
grep -Eq 'image import .*\.tar .*\.rootfs --alias vdm-opencode-base/test' "$MOCK_INCUS_LOG"

printf 'tampered\n' >> "$(find "$output_dir/payload" -type f | head -n 1)"
if "$ROOT_DIR/scripts/verify-artifact.sh" "$output_dir" >/dev/null 2>&1; then
    printf 'Tampered payload should have been rejected.\n' >&2
    exit 1
fi

printf 'Image package round-trip test passed.\n'
