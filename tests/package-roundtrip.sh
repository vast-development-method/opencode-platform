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
        (.image_fingerprint | test("^[a-f0-9]{64}$")) and
        (.worker_node_version | startswith("24.")) and
        (.payload | length == 2)
    ' "$output_dir/manifest.json" >/dev/null

(
    cd "$output_dir"
    sha256sum --check --strict SHA256SUMS
)

"$ROOT_DIR/scripts/import-image-package.sh" "$output_dir" "vdm-opencode-base/test"
grep -Eq 'image import .*\.tar .*\.rootfs --alias vdm-opencode-base/test' "$MOCK_INCUS_LOG"

"$ROOT_DIR/scripts/ductor-image-config.sh" "$output_dir" default > "$tmp_dir/ductor.json"
jq -e '.image_source_project == "default" and .image_import == null' "$tmp_dir/ductor.json" >/dev/null
"$ROOT_DIR/scripts/ductor-image-config.sh" "$output_dir" default \
    https://images.example.test/approved > "$tmp_dir/ductor.json"
jq -e --argjson manifest "$(cat "$output_dir/manifest.json")" '
    .image_fingerprint == $manifest.image_fingerprint
    and .worker_node_version == $manifest.worker_node_version
    and (.image_import.metadata_url | startswith("https://images.example.test/approved/payload/"))
    and (.image_import.metadata_sha256 | test("^[a-f0-9]{64}$"))
    and (.image_import.disk_sha256 | test("^[a-f0-9]{64}$"))
  ' "$tmp_dir/ductor.json" >/dev/null

if MOCK_INCUS_NODE_VERSION=22.20.0 \
    "$ROOT_DIR/scripts/import-image-package.sh" "$output_dir" "vdm-opencode-base/wrong-node" > "$tmp_dir/error" 2>&1; then
    printf 'An imported image with false Node attestation was accepted.\n' >&2
    exit 1
fi
grep -F 'Imported image fingerprint or Node attestation does not match' "$tmp_dir/error" >/dev/null
if MOCK_INCUS_FINGERPRINT="$(printf 'b%.0s' {1..64})" \
    "$ROOT_DIR/scripts/import-image-package.sh" "$output_dir" "vdm-opencode-base/wrong-image" > "$tmp_dir/error" 2>&1; then
    printf 'An imported image with the wrong fingerprint was accepted.\n' >&2
    exit 1
fi
if "$ROOT_DIR/scripts/ductor-image-config.sh" "$output_dir" default \
    https://operator:secret@images.example.test/approved > "$tmp_dir/error" 2>&1; then
    printf 'A package URL containing credentials was accepted.\n' >&2
    exit 1
fi

printf 'tampered\n' >> "$(find "$output_dir/payload" -type f | head -n 1)"
if "$ROOT_DIR/scripts/verify-artifact.sh" "$output_dir" >/dev/null 2>&1; then
    printf 'Tampered payload should have been rejected.\n' >&2
    exit 1
fi
if "$ROOT_DIR/scripts/ductor-image-config.sh" "$output_dir" default >/dev/null 2>&1; then
    printf 'A Ductor identity was emitted from a tampered package.\n' >&2
    exit 1
fi

printf 'Image package round-trip test passed.\n'
