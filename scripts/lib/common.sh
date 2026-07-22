#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/manifest/platform.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/manifest/toolchain.env"

log() {
    printf '\n\033[1;34m==> %s\033[0m\n' "$*"
}

warn() {
    printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2
}

die() {
    printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

incus_cmd() {
    if incus info >/dev/null 2>&1; then
        incus "$@"
    else
        sudo incus "$@"
    fi
}

project_cmd() {
    incus_cmd --project "$INCUS_PROJECT" "$@"
}

wait_for_vm() {
    local name="$1"
    local attempt
    for attempt in $(seq 1 180); do
        if project_cmd exec "$name" --mode=non-interactive -- true >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

variant_exists() {
    case "$1" in
        base|php|python|cpp|typescript|full) return 0 ;;
        *) return 1 ;;
    esac
}

image_alias() {
    printf '%s-%s/%s' "$INCUS_IMAGE_PREFIX" "$1" "$PLATFORM_VERSION"
}
