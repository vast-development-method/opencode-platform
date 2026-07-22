#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

PACKAGE_DIR="${1:-}"
REQUESTED_ALIAS="${2:-}"
[ -d "$PACKAGE_DIR" ] || die "Usage: $0 PACKAGE_DIRECTORY [IMAGE_ALIAS]"
[ -f "$PACKAGE_DIR/manifest.json" ] || die "Package manifest is missing."
[ -f "$PACKAGE_DIR/SHA256SUMS" ] || die "Package checksums are missing."

(
    cd "$PACKAGE_DIR"
    sha256sum --check --strict SHA256SUMS
)

jq -e '
    .schema == 1 and
    (.platform | type == "string") and
    (.version | type == "string") and
    (.variant | type == "string") and
    (.payload | type == "array" and length > 0)
' "$PACKAGE_DIR/manifest.json" >/dev/null || die "Package manifest is invalid."

mapfile -t payload_names < <(jq -r '.payload[].name' "$PACKAGE_DIR/manifest.json")
metadata_files=()
data_files=()
for name in "${payload_names[@]}"; do
    [[ "$name" != */* && "$name" != .* ]] || die "Unsafe payload name: $name"
    [ -f "$PACKAGE_DIR/$name" ] || die "Package payload is missing: $name"
    if tar -tf "$PACKAGE_DIR/$name" 2>/dev/null | grep -Eq '^(\./)?metadata\.yaml$'; then
        metadata_files+=("$PACKAGE_DIR/$name")
    else
        data_files+=("$PACKAGE_DIR/$name")
    fi
done
[ "${#metadata_files[@]}" -le 1 ] || die "Package contains more than one metadata archive."
payload_files=("${metadata_files[@]}" "${data_files[@]}")

alias_name="${REQUESTED_ALIAS:-$(jq -r '.image' "$PACKAGE_DIR/manifest.json")}"
[ -n "$alias_name" ] && [ "$alias_name" != null ] || die "No image alias was supplied or recorded."
project_cmd image show "$alias_name" >/dev/null 2>&1 && die "Image alias already exists: $alias_name"

project_cmd image import "${payload_files[@]}" --alias "$alias_name"
project_cmd image set-property "$alias_name" org.vdm.platform "$(jq -r '.platform' "$PACKAGE_DIR/manifest.json")"
project_cmd image set-property "$alias_name" org.vdm.version "$(jq -r '.version' "$PACKAGE_DIR/manifest.json")"
project_cmd image set-property "$alias_name" org.vdm.variant "$(jq -r '.variant' "$PACKAGE_DIR/manifest.json")"

log "Imported $alias_name"
