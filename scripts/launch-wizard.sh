#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

prompt() {
    local label="$1"
    local default="${2:-}"
    local value
    if [ -n "$default" ]; then
        read -r -p "$label [$default]: " value
        printf '%s\n' "${value:-$default}"
    else
        read -r -p "$label: " value
        [ -n "$value" ] || die "$label is required"
        printf '%s\n' "$value"
    fi
}

IMAGE="$(prompt "Image (${PLATFORM_IMAGES[*]})" base)"
variant_exists "$IMAGE" || die "Unknown image: $IMAGE"
INSTANCE="$(prompt "Instance name")"
[[ "$INSTANCE" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || die "Unsafe instance name"
OWNER="$(prompt "Owner" "${USER:-unknown}")"
TEAM="$(prompt "Team" individual)"
TRUST="$(prompt "Repository trust (trusted/untrusted)" trusted)"
case "$TRUST" in trusted|untrusted) ;; *) die "Trust must be trusted or untrusted" ;; esac

default_policy="${PLATFORM_IMAGE_DEFAULT_POLICY[$IMAGE]}"
[ "$TRUST" = untrusted ] && default_policy=offline
POLICY="$(prompt "Network policy" "$default_policy")"
policy_exists "$POLICY" || die "Unknown policy: $POLICY"
SIZE="$(prompt "Resource size" "${PLATFORM_IMAGE_DEFAULT_SIZE[$IMAGE]}")"
size_exists "$SIZE" || die "Unknown size: $SIZE"
TTL="$(prompt "Maximum session TTL" "$DEFAULT_SESSION_TTL")"
TTL_SECONDS="$(duration_to_seconds "$TTL")"
((TTL_SECONDS >= 60 && TTL_SECONDS <= 86400)) || die "TTL must be between one minute and 24 hours"
WORKSPACE="$(prompt "Workspace lifecycle (disposable/retained)" disposable)"
case "$WORKSPACE" in disposable|retained) ;; *) die "Workspace lifecycle must be disposable or retained" ;; esac
REPOSITORIES="$(prompt "Allowed repositories (comma-separated, metadata only)" none)"
PROVIDERS="$(prompt "Allowed model routes (comma-separated)" local-default)"
BUDGET="$(prompt "Session budget in USD (0 means externally enforced)" 0)"
[[ "$BUDGET" =~ ^[0-9]+([.][0-9]{1,2})?$ ]] || die "Budget must be a non-negative number"

export VDM_SESSION_OWNER="$OWNER"
export VDM_SESSION_TEAM="$TEAM"
export VDM_REPOSITORY_TRUST="$TRUST"
export VDM_WORKSPACE_LIFECYCLE="$WORKSPACE"
export VDM_REPOSITORY_ALLOWLIST="$REPOSITORIES"
export VDM_PROVIDER_ALLOWLIST="$PROVIDERS"
export VDM_SESSION_BUDGET_USD="$BUDGET"
export VDM_SESSION_TTL="$TTL"

"$SCRIPT_DIR/launch-vm.sh" "$IMAGE" "$INSTANCE" "$POLICY" "$SIZE"

printf '\nCreated %s with policy=%s, size=%s, trust=%s, TTL=%s.\n' \
    "$INSTANCE" "$POLICY" "$SIZE" "$TRUST" "$TTL"
printf 'Create its runtime credentials with: %s/create-runtime-env.sh %s\n' "$SCRIPT_DIR" "$INSTANCE"
printf 'Start it with: %s/start-session.sh %s <runtime-env> %s\n' "$SCRIPT_DIR" "$INSTANCE" "$TTL"
