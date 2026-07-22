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
GITEA_PACKAGE_USER="${GITEA_PACKAGE_USER:-package-publisher}"
[[ "$GITEA_PACKAGE_USER" =~ ^[A-Za-z0-9_.@+-]+$ ]] || die "Unsafe Gitea package user"
[[ "$GITEA_PACKAGE_TOKEN" != *$'\n'* && "$GITEA_PACKAGE_TOKEN" != *'"'* ]] || die "Unsafe Gitea token encoding"

PACKAGE_NAME="${GITEA_PACKAGE_NAME:-vdm-opencode-${VARIANT}-${ARCHITECTURE}}"
ARTIFACT_ID="$(artifact_id "$VARIANT" "$ARCHITECTURE")"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
BUNDLE="$STAGING/${ARTIFACT_ID}.tar.zst"

tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
    -C "$PACKAGE_DIR" -cf - . | zstd --quiet --threads=0 -19 -o "$BUNDLE"
BUNDLE_SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"
BUNDLE_SIZE="$(stat -c '%s' "$BUNDLE")"

jq -n \
    --arg schema "1" \
    --arg artifact_id "$ARTIFACT_ID" \
    --arg version "$PLATFORM_VERSION" \
    --arg variant "$VARIANT" \
    --arg architecture "$ARCHITECTURE" \
    --arg bundle "$(basename "$BUNDLE")" \
    --arg sha256 "$BUNDLE_SHA" \
    --argjson bytes "$BUNDLE_SIZE" \
    --arg published_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema:($schema|tonumber),artifact_id:$artifact_id,version:$version,variant:$variant,
      architecture:$architecture,bundle:$bundle,sha256:$sha256,bytes:$bytes,published_at:$published_at}' \
    > "$STAGING/release-entry.json"

if [ -n "${COSIGN_KEY:-}" ]; then
    cosign sign-blob --yes --tlog-upload=false --key "$COSIGN_KEY" \
        --bundle "$STAGING/release-entry.sigstore.json" "$STAGING/release-entry.json"
elif [ "${VDM_RELEASE_MODE:-false}" = true ]; then
    die "COSIGN_KEY is required for tagged release publication"
fi

MARKER="$STAGING/${ARTIFACT_ID}.complete.tar"
tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
    -C "$STAGING" -cf "$MARKER" release-entry.json \
    $([ -f "$STAGING/release-entry.sigstore.json" ] && printf '%s' release-entry.sigstore.json)

gitea_curl() {
    local method="${1:?method required}"
    local url="${2:?url required}"
    shift 2
    printf 'user = "%s:%s"\n' "$GITEA_PACKAGE_USER" "$GITEA_PACKAGE_TOKEN" |
        curl --config - --request "$method" --silent --show-error \
            --retry 4 --retry-all-errors --connect-timeout 15 "$@" "$url"
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
    url="${GITEA_BASE_URL}/api/packages/${GITEA_PACKAGE_OWNER}/generic/${PACKAGE_NAME}/${PLATFORM_VERSION}/${name}"
    status="$(gitea_curl HEAD "$url" --output /dev/null --write-out '%{http_code}')"
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

# The completion marker is deliberately uploaded last. Consumers must ignore
# an artifact unless this immutable marker exists and verifies.
publish_immutable "$BUNDLE"
publish_immutable "$MARKER"
log "Published atomic package marker for ${PACKAGE_NAME}/${PLATFORM_VERSION}"
