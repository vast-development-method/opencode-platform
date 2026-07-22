#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/manifest/generated/platform.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/manifest/platform.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/manifest/toolchain.env"

if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
    set +a
fi

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

duration_to_seconds() {
    local value="${1:?duration required}"
    local amount
    local suffix

    [[ "$value" =~ ^([1-9][0-9]*)(s|m|h|d)?$ ]] ||
        die "Invalid duration: $value (use seconds or a suffix: s, m, h, d)"
    amount="${BASH_REMATCH[1]}"
    suffix="${BASH_REMATCH[2]:-s}"
    case "$suffix" in
        s) printf '%s\n' "$amount" ;;
        m) printf '%s\n' "$((amount * 60))" ;;
        h) printf '%s\n' "$((amount * 3600))" ;;
        d) printf '%s\n' "$((amount * 86400))" ;;
    esac
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
    local _
    for _ in $(seq 1 180); do
        if project_cmd exec "$name" --mode=non-interactive -- true >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

variant_exists() {
    [[ -n "${1:-}" && -v "PLATFORM_IMAGE_COMPONENTS[$1]" ]]
}

policy_exists() {
    [[ -n "${1:-}" && -v "PLATFORM_POLICY_STATUS[$1]" ]]
}

size_exists() {
    [[ -n "${1:-}" && -v "PLATFORM_SIZE_CPUS[$1]" ]]
}

image_has_component() {
    local image="${1:?image required}"
    local wanted="${2:?component required}"
    local component

    for component in ${PLATFORM_IMAGE_COMPONENTS[$image]}; do
        [[ "$component" == "$wanted" ]] && return 0
    done
    return 1
}

canonical_architecture() {
    local raw="${1:-$(uname -m)}"
    [[ -v "PLATFORM_ARCH_ALIASES[$raw]" ]] || die "Unsupported architecture: $raw"
    printf '%s\n' "${PLATFORM_ARCH_ALIASES[$raw]}"
}

image_alias() {
    local variant="${1:?variant required}"
    local architecture="${2:-$(canonical_architecture)}"
    printf '%s-%s/%s-%s' "$INCUS_IMAGE_PREFIX" "$variant" "$PLATFORM_VERSION" "$architecture"
}

artifact_id() {
    local variant="${1:?variant required}"
    local architecture="${2:-$(canonical_architecture)}"
    printf '%s-%s-%s-%s' "$INCUS_IMAGE_PREFIX" "$variant" "$PLATFORM_VERSION" "$architecture"
}
