#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/variant-selection.sh"

RAW_VARIANTS="${LOCAL_BUILD_VARIANTS:-all}"
PUBLISH_GITEA="${LOCAL_PUBLISH_GITEA:-false}"
REQUIRE_CLEAN="${LOCAL_REQUIRE_CLEAN:-true}"
REQUIRE_TAG="${LOCAL_REQUIRE_TAG:-false}"

normalize_bool() {
    case "${1,,}" in
        true|1|yes) printf 'true' ;;
        false|0|no) printf 'false' ;;
        *) die "Boolean value must be true or false: $1" ;;
    esac
}

PUBLISH_GITEA="$(normalize_bool "$PUBLISH_GITEA")"
REQUIRE_CLEAN="$(normalize_bool "$REQUIRE_CLEAN")"
REQUIRE_TAG="$(normalize_bool "$REQUIRE_TAG")"

variants=()
parse_variant_selection "$RAW_VARIANTS" variants || die "Invalid LOCAL_BUILD_VARIANTS value."

version_file="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
[ -n "$version_file" ] || die "VERSION is empty."
[ "$version_file" = "$PLATFORM_VERSION" ] ||
    die "VERSION ($version_file) does not match PLATFORM_VERSION ($PLATFORM_VERSION)."

require_command git
require_command flock
require_command sha256sum

if [ "$REQUIRE_CLEAN" = true ]; then
    git -C "$ROOT_DIR" diff --quiet --ignore-submodules --
    git -C "$ROOT_DIR" diff --cached --quiet --ignore-submodules --
    [ -z "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=normal)" ] ||
        die "The source tree is not clean. Commit or remove local changes, or set LOCAL_REQUIRE_CLEAN=false for a non-release build."
fi

source_revision="$(git -C "$ROOT_DIR" rev-parse --verify HEAD)"
source_tag="$(git -C "$ROOT_DIR" tag --points-at "$source_revision" | grep -Fx "v$PLATFORM_VERSION" || true)"
if [ "$REQUIRE_TAG" = true ] && [ -z "$source_tag" ]; then
    die "HEAD must be tagged v$PLATFORM_VERSION when LOCAL_REQUIRE_TAG=true."
fi

if [ "$PUBLISH_GITEA" = true ]; then
    : "${GITEA_BASE_URL:?Set GITEA_BASE_URL}"
    : "${GITEA_PACKAGE_OWNER:?Set GITEA_PACKAGE_OWNER}"
    : "${GITEA_PACKAGE_USER:?Set GITEA_PACKAGE_USER}"
    : "${GITEA_PACKAGE_TOKEN:?Set GITEA_PACKAGE_TOKEN in this process only}"
fi

"$ROOT_DIR/tests/validate-repository.sh"
"$SCRIPT_DIR/ci/check-incus-runner.sh"

install -d -m 0750 "$ROOT_DIR/build"
exec 9>"$ROOT_DIR/build/.local-release.lock"
flock -n 9 || die "Another local image release is already running."

log "Local image release $PLATFORM_VERSION from $source_revision"
log "Variants: ${variants[*]}"

for variant in "${variants[@]}"; do
    log "Building $variant"
    "$SCRIPT_DIR/build-image.sh" "$variant"

    package_dir="$ROOT_DIR/build/packages/$PLATFORM_VERSION/$variant"
    "$SCRIPT_DIR/package-image.sh" "$variant" "$package_dir"
    (
        cd "$package_dir"
        sha256sum --check --strict SHA256SUMS
    )

    if [ "$PUBLISH_GITEA" = true ]; then
        "$SCRIPT_DIR/publish-gitea-package.sh" "$variant" "$package_dir"
    fi
done

log "Local release completed"
printf 'Version: %s\nRevision: %s\nPackages: %s\n' \
    "$PLATFORM_VERSION" "$source_revision" "$ROOT_DIR/build/packages/$PLATFORM_VERSION"
if [ "$PUBLISH_GITEA" = true ]; then
    printf 'Published to: %s/api/packages/%s\n' "$GITEA_BASE_URL" "$GITEA_PACKAGE_OWNER"
fi
