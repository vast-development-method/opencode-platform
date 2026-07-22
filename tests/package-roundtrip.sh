#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export PATH="$ROOT_DIR/tests/fixtures:$PATH"
export MOCK_INCUS_LOG="$tmp_dir/incus.log"
output_dir="$tmp_dir/package"

"$ROOT_DIR/scripts/package-image.sh" base "$output_dir"

jq -e '
    .schema == 1 and
    .platform == "vdm-opencode-platform" and
    .version == "0.2.0" and
    .variant == "base" and
    (.payload | length == 2)
' "$output_dir/manifest.json" >/dev/null

(
    cd "$output_dir"
    sha256sum --check --strict SHA256SUMS
)

"$ROOT_DIR/scripts/import-image-package.sh" "$output_dir" "vdm-opencode-base/test"
grep -Eq 'image import .*\.tar .*\.rootfs --alias vdm-opencode-base/test' "$MOCK_INCUS_LOG"

printf 'Image package round-trip test passed.\n'
