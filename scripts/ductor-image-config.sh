#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PACKAGE_DIR="${1:-}"
SOURCE_PROJECT="${2:-}"
PAYLOAD_BASE_URL="${3:-}"
[ -d "$PACKAGE_DIR" ] && [ -n "$SOURCE_PROJECT" ] || {
    printf 'Usage: %s PACKAGE_DIRECTORY IMAGE_SOURCE_PROJECT [HTTPS_PACKAGE_BASE_URL]\n' "$0" >&2
    exit 2
}
[[ "$SOURCE_PROJECT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    printf 'Invalid Incus image source project.\n' >&2
    exit 2
}
# The same checksum and optional signature gate as the normal import workflow.
"$SCRIPT_DIR/verify-artifact.sh" "$PACKAGE_DIR" >&2
identity="$(jq -ce --arg project "$SOURCE_PROJECT" '
    select((.image_fingerprint | type == "string" and test("^[a-f0-9]{64}$"))
      and (.worker_node_version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$")))
    | select(.worker_node_version | split(".") | map(tonumber)
        | (.[0] == 24 and .[1] >= 16) or (.[0] == 26 and .[1] >= 1))
    | {image_fingerprint,worker_node_version,image_source_project:$project}
  ' "$PACKAGE_DIR/manifest.json")" || {
    printf 'Package lacks a compatible, verified Node image identity. Rebuild it before use with Ductor.\n' >&2
    exit 1
}
if [ -z "$PAYLOAD_BASE_URL" ]; then
    jq . <<< "$identity"
    exit 0
fi
[[ "$PAYLOAD_BASE_URL" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/-]*)?$ &&
   "$PAYLOAD_BASE_URL" != *'/../'* && "$PAYLOAD_BASE_URL" != */.. ]] || {
    printf 'Package base URL must be HTTPS without credentials, query or fragment.\n' >&2
    exit 2
}
metadata=""
disk=""
while IFS= read -r name; do
    [[ "$name" =~ ^payload/[A-Za-z0-9._-]+$ ]] || {
        printf 'Unsafe payload name in package.\n' >&2
        exit 1
    }
    if tar -tf "$PACKAGE_DIR/$name" 2>/dev/null | grep -Eq '^(\./)?metadata\.yaml$'; then
        [ -z "$metadata" ] || { printf 'Multiple image metadata archives.\n' >&2; exit 1; }
        metadata="$name"
    else
        [ -z "$disk" ] || { printf 'Multiple image disk files.\n' >&2; exit 1; }
        disk="$name"
    fi
done < <(jq -r '.payload[].name' "$PACKAGE_DIR/manifest.json")
[ -n "$metadata" ] && [ -n "$disk" ] || {
    printf 'Ductor download import requires a split Incus VM export; use the normal package import for unified images.\n' >&2
    exit 1
}
jq --argjson identity "$identity" --arg base "${PAYLOAD_BASE_URL%/}" \
    --arg metadata "$metadata" --arg disk "$disk" '
    $identity + {image_import:{
      metadata_url:($base + "/" + $metadata),
      metadata_sha256:(.payload[] | select(.name == $metadata) | .sha256),
      disk_url:($base + "/" + $disk),
      disk_sha256:(.payload[] | select(.name == $disk) | .sha256)
    }}' "$PACKAGE_DIR/manifest.json"
