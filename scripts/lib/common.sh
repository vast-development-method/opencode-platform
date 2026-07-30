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

declare -ag VDM_INCUS_COMMAND=()

resolve_incus_command() {
    local direct_error
    local sudo_mode="${VDM_INCUS_USE_SUDO:-false}"

    (("${#VDM_INCUS_COMMAND[@]}" == 0)) || return 0
    require_command incus
    case "$sudo_mode" in
        true|false) ;;
        *) die "VDM_INCUS_USE_SUDO must be true or false" ;;
    esac

    if direct_error="$(incus info 2>&1)"; then
        VDM_INCUS_COMMAND=(incus)
        return 0
    fi

    if [ "$sudo_mode" != true ]; then
        if [ "${EUID:-$(id -u)}" -eq 0 ]; then
            die "Incus is installed but its daemon is unavailable: ${direct_error:-no diagnostic returned}"
        fi
        die "Direct Incus access failed. Ensure the daemon is running and the operator has active incus-admin membership (log out and back in after bootstrap). Set VDM_INCUS_USE_SUDO=true only for an explicitly privileged invocation. Incus reported: ${direct_error:-no diagnostic returned}"
    fi

    require_command sudo
    if [ -t 0 ] && [ -t 1 ]; then
        sudo incus info >/dev/null ||
            die "Unable to contact Incus through the explicitly enabled sudo path"
        VDM_INCUS_COMMAND=(sudo incus)
    else
        sudo -n incus info >/dev/null ||
            die "Non-interactive sudo access to Incus is unavailable; grant direct incus-admin access or configure a narrowly scoped non-interactive policy"
        VDM_INCUS_COMMAND=(sudo -n incus)
    fi
}

incus_cmd() {
    resolve_incus_command
    "${VDM_INCUS_COMMAND[@]}" "$@"
}

project_cmd() {
    incus_cmd --project "$INCUS_PROJECT" "$@"
}

default_cmd() {
    incus_cmd --project default "$@"
}

version_at_least() {
    local actual="${1:?actual version required}"
    local minimum="${2:?minimum version required}"

    [ "$(printf '%s\n%s\n' "$minimum" "$actual" | sort -V | head -n 1)" = "$minimum" ]
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

stop_guest_sessions() {
    local name="${1:?instance name required}"

    # The single-quoted command is intentionally evaluated inside the guest.
    # shellcheck disable=SC2016
    project_cmd exec "$name" -- bash -c \
        'systemctl list-units --type=service --all --no-legend "vdm-opencode-*.service" |
         awk "{print \$1}" | xargs -r systemctl stop' >/dev/null 2>&1 ||
        true
}

cleanup_guest_runtime() {
    local name="${1:?instance name required}"

    # `find` receives the pattern literally and evaluates it in the guest.
    project_cmd exec "$name" -- find /run \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        \( -name vdm-opencode-input -o -name 'vdm-opencode-*' \) \
        -exec rm -rf -- {} + >/dev/null 2>&1 ||
        true
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
    local architecture="${2:-$(canonical_architecture "$(uname -m)")}"
    printf '%s-%s/%s-%s' "$INCUS_IMAGE_PREFIX" "$variant" "$PLATFORM_VERSION" "$architecture"
}

artifact_id() {
    local variant="${1:?variant required}"
    local architecture="${2:-$(canonical_architecture "$(uname -m)")}"
    printf '%s-%s-%s-%s' "$INCUS_IMAGE_PREFIX" "$variant" "$PLATFORM_VERSION" "$architecture"
}
