#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

VARIANT="${1:-}"
ARCHITECTURE="$(canonical_architecture "${VDM_BUILD_ARCHITECTURE:-}")"
PACKAGE_DIR="${2:-$ROOT_DIR/build/packages/${PLATFORM_VERSION}/${ARCHITECTURE}/${VARIANT}}"
variant_exists "$VARIANT" || die "Unknown variant: $VARIANT"
[ -d "$PACKAGE_DIR" ] || die "Package directory missing: $PACKAGE_DIR"
"$SCRIPT_DIR/verify-artifact.sh" "$PACKAGE_DIR"

: "${GITEA_PACKAGE_OWNER:?Set GITEA_PACKAGE_OWNER}"
: "${GITEA_PACKAGE_TOKEN:?Set GITEA_PACKAGE_TOKEN in the CI runtime only}"
: "${GITEA_BASE_URL:?Set GITEA_BASE_URL}"
GITEA_PACKAGE_USER="${GITEA_PACKAGE_USER:-package-publisher}"
[[ "$GITEA_PACKAGE_USER" =~ ^[A-Za-z0-9_.@+-]+$ ]] || die "Unsafe Gitea package user"
[[ "$GITEA_PACKAGE_OWNER" =~ ^[A-Za-z0-9_.-]+$ ]] || die "Unsafe Gitea package owner"
[[ "$GITEA_PACKAGE_TOKEN" != *$'\n'* &&
    "$GITEA_PACKAGE_TOKEN" != *$'\r'* &&
    "$GITEA_PACKAGE_TOKEN" != *'"'* ]] ||
    die "Unsafe Gitea token encoding"

PACKAGE_NAME="${GITEA_PACKAGE_NAME:-vdm-opencode-${VARIANT}-${ARCHITECTURE}}"
[[ "$PACKAGE_NAME" =~ ^[A-Za-z0-9_.-]+$ ]] || die "Unsafe Gitea package name"
ARTIFACT_ID="$(artifact_id "$VARIANT" "$ARCHITECTURE")"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
BUNDLE="$STAGING/${ARTIFACT_ID}.tar.zst"

tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
    -C "$PACKAGE_DIR" -cf - . | zstd --quiet --threads=0 -19 -o "$BUNDLE"
BUNDLE_SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
BUNDLE_SIZE="$(stat -c '%s' "$BUNDLE")"
PACKAGED_AT="$(
    jq -er '
        .packaged_at
        | select(
            type == "string"
            and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
        )
    ' "$PACKAGE_DIR/manifest.json"
)" || die "manifest.json has no valid UTC packaged_at timestamp"

jq -n \
    --arg schema "1" \
    --arg artifact_id "$ARTIFACT_ID" \
    --arg version "$PLATFORM_VERSION" \
    --arg variant "$VARIANT" \
    --arg architecture "$ARCHITECTURE" \
    --arg bundle "$(basename "$BUNDLE")" \
    --arg sha256 "$BUNDLE_SHA" \
    --argjson bytes "$BUNDLE_SIZE" \
    --arg published_at "$PACKAGED_AT" \
    '{schema:($schema|tonumber),artifact_id:$artifact_id,version:$version,variant:$variant,
      architecture:$architecture,bundle:$bundle,sha256:$sha256,bytes:$bytes,published_at:$published_at}' \
    > "$STAGING/release-entry.json"

gitea_curl() {
    local method="${1:?method required}"
    local url="${2:?url required}"
    local escaped_token
    shift 2
    escaped_token="${GITEA_PACKAGE_TOKEN//\\/\\\\}"
    printf 'user = "%s:%s"\n' "$GITEA_PACKAGE_USER" "$escaped_token" |
        curl --config - --request "$method" --silent --show-error \
            --retry 4 --retry-all-errors --connect-timeout 15 "$@" "$url"
}

object_url() {
    local name="${1:?object name required}"
    printf '%s/api/packages/%s/generic/%s/%s/%s' \
        "$GITEA_BASE_URL" \
        "$GITEA_PACKAGE_OWNER" \
        "$PACKAGE_NAME" \
        "$PLATFORM_VERSION" \
        "$name"
}

remote_status() {
    local name="${1:?object name required}"
    gitea_curl HEAD "$(object_url "$name")" \
        --output /dev/null \
        --write-out '%{http_code}'
}

publish_immutable() {
    local file="${1:?file required}"
    local name
    local url
    local status
    local remote
    local local_sha
    local remote_sha
    name="$(basename "$file")"
    url="$(object_url "$name")"
    status="$(remote_status "$name")"
    case "$status" in
        404)
            gitea_curl PUT "$url" --upload-file "$file" --fail-with-body >/dev/null
            ;;
        200) ;;
        *) die "Unexpected Gitea response for $name: HTTP $status" ;;
    esac
    remote="$(mktemp)"
    gitea_curl GET "$url" --fail-with-body --output "$remote"
    local_sha="$(sha256sum "$file" | awk '{print $1}')"
    remote_sha="$(sha256sum "$remote" | awk '{print $1}')"
    rm -f "$remote"
    [ "$local_sha" = "$remote_sha" ] ||
        die "Published object differs from local object: $name"
}

validate_remote_marker() {
    local marker_name="${1:?marker name required}"
    local remote_marker="$STAGING/remote-marker.tar"
    local remote_entry="$STAGING/remote-release-entry.json"
    local remote_signature="$STAGING/remote-release-entry.sigstore.json"
    local name
    local release_entries=0
    local signature_entries=0
    local -a entries=()

    gitea_curl GET "$(object_url "$marker_name")" \
        --fail-with-body \
        --output "$remote_marker"
    mapfile -t entries < <(tar -tf "$remote_marker")
    (("${#entries[@]}" > 0)) || die "Remote completion marker is empty: $marker_name"
    for name in "${entries[@]}"; do
        case "$name" in
            release-entry.json) release_entries=$((release_entries + 1)) ;;
            release-entry.sigstore.json) signature_entries=$((signature_entries + 1)) ;;
            *) die "Remote completion marker contains an unsafe or unexpected member: $name" ;;
        esac
    done
    [ "$release_entries" -eq 1 ] ||
        die "Remote completion marker must contain exactly one release-entry.json"
    [ "$signature_entries" -le 1 ] ||
        die "Remote completion marker contains duplicate signature entries"

    tar --extract --to-stdout \
        --file "$remote_marker" \
        release-entry.json > "$remote_entry" ||
        die "Unable to read release-entry.json from remote marker"
    cmp -s "$STAGING/release-entry.json" "$remote_entry" ||
        die "Published completion marker describes a different release: $marker_name"

    if [ "${VDM_RELEASE_MODE:-false}" = true ] && [ "$signature_entries" -ne 1 ]; then
        die "Published release marker is unsigned: $marker_name"
    fi
    if [ "$signature_entries" -eq 1 ] && [ -n "${COSIGN_PUBLIC_KEY:-}" ]; then
        require_command cosign
        tar --extract --to-stdout \
            --file "$remote_marker" \
            release-entry.sigstore.json > "$remote_signature" ||
            die "Unable to read the signature from remote marker"
        cosign verify-blob \
            --key "$COSIGN_PUBLIC_KEY" \
            --bundle "$remote_signature" \
            "$remote_entry" >/dev/null
    elif [ "${VDM_RELEASE_MODE:-false}" = true ]; then
        die "COSIGN_PUBLIC_KEY is required to validate an existing signed release marker"
    fi
}

# The completion marker is deliberately uploaded last. Consumers must ignore
# an artifact unless this immutable marker exists and verifies.
publish_immutable "$BUNDLE"

MARKER="$STAGING/${ARTIFACT_ID}.complete.tar"
marker_status="$(remote_status "$(basename "$MARKER")")"
case "$marker_status" in
    200)
        validate_remote_marker "$(basename "$MARKER")"
        log "Existing atomic package marker is valid for ${PACKAGE_NAME}/${PLATFORM_VERSION}"
        exit 0
        ;;
    404) ;;
    *) die "Unexpected Gitea response for $(basename "$MARKER"): HTTP $marker_status" ;;
esac

if [ -n "${COSIGN_KEY:-}" ]; then
    require_command cosign
    cosign sign-blob --yes --tlog-upload=false --key "$COSIGN_KEY" \
        --bundle "$STAGING/release-entry.sigstore.json" "$STAGING/release-entry.json"
elif [ "${VDM_RELEASE_MODE:-false}" = true ]; then
    die "COSIGN_KEY is required for tagged release publication"
fi

marker_files=(release-entry.json)
if [ -f "$STAGING/release-entry.sigstore.json" ]; then
    marker_files+=(release-entry.sigstore.json)
fi
tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
    -C "$STAGING" -cf "$MARKER" "${marker_files[@]}"

publish_immutable "$MARKER"
log "Published atomic package marker for ${PACKAGE_NAME}/${PLATFORM_VERSION}"
