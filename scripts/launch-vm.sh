#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

VARIANT="${1:-}"
NAME="${2:-}"
POLICY="${3:-${PLATFORM_IMAGE_DEFAULT_POLICY[$VARIANT]:-}}"
SIZE="${4:-${PLATFORM_IMAGE_DEFAULT_SIZE[$VARIANT]:-}}"
variant_exists "$VARIANT" || die "Variant must be one of: ${PLATFORM_IMAGES[*]}"
[ -n "$NAME" ] || die "Usage: $0 VARIANT INSTANCE_NAME [POLICY] [SIZE]"
policy_exists "$POLICY" || die "Unknown policy: $POLICY"
size_exists "$SIZE" || die "Unknown size: $SIZE"
case "${PLATFORM_POLICY_STATUS[$POLICY]}" in
    ready) ;;
    experimental)
        [ "${VDM_ALLOW_EXPERIMENTAL_POLICY:-false}" = true ] ||
            die "Policy $POLICY is experimental; set VDM_ALLOW_EXPERIMENTAL_POLICY=true to acknowledge it."
        ;;
    *) die "Policy $POLICY is blocked until its gateway and enforcement dependencies are configured." ;;
esac

ALIAS="$(image_alias "$VARIANT")"
project_cmd image show "$ALIAS" >/dev/null 2>&1 || die "Image not found: $ALIAS. Build or import it first."
project_cmd info "$NAME" >/dev/null 2>&1 && die "Instance already exists: $NAME"

OWNER="${VDM_SESSION_OWNER:-${USER:-unknown}}"
TEAM="${VDM_SESSION_TEAM:-individual}"
REPOSITORY_TRUST="${VDM_REPOSITORY_TRUST:-trusted}"
REPOSITORY_ALLOWLIST="${VDM_REPOSITORY_ALLOWLIST:-none}"
PROVIDER_ALLOWLIST="${VDM_PROVIDER_ALLOWLIST:-local-default}"
SESSION_BUDGET="${VDM_SESSION_BUDGET_USD:-0}"
SESSION_TTL="${VDM_SESSION_TTL:-$DEFAULT_SESSION_TTL}"
WORKSPACE_LIFECYCLE="${VDM_WORKSPACE_LIFECYCLE:-disposable}"

[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || die "Unsafe instance name: $NAME"
[ -n "$OWNER" ] || die "Session owner cannot be empty"
[[ "$SESSION_BUDGET" =~ ^[0-9]+([.][0-9]{1,2})?$ ]] ||
    die "Session budget must be a non-negative number with at most two decimal places"
TTL_SECONDS="$(duration_to_seconds "$SESSION_TTL")"
((TTL_SECONDS >= 60 && TTL_SECONDS <= 86400)) ||
    die "Session TTL must be between 60 seconds and 24 hours"
case "$REPOSITORY_TRUST" in trusted|untrusted) ;; *) die "Repository trust must be trusted or untrusted" ;; esac
case "$WORKSPACE_LIFECYCLE" in disposable|retained) ;; *) die "Workspace lifecycle must be disposable or retained" ;; esac

created=false
cleanup_failed_launch() {
    local status=$?
    trap - EXIT
    set +e
    if [ "$status" -ne 0 ] && [ "$created" = true ]; then
        warn "Launch failed; removing the incomplete instance created by this invocation: $NAME"
        project_cmd delete "$NAME" --force >/dev/null 2>&1 ||
            warn "Automatic cleanup failed; inspect and remove $NAME before retrying"
    fi
    exit "$status"
}
trap cleanup_failed_launch EXIT

project_cmd init "$ALIAS" "$NAME" --vm \
    --profile "vdm-opencode-${VARIANT}" \
    --profile "vdm-size-$SIZE" \
    --profile "vdm-policy-$POLICY" \
    --config "user.vdm.owner=$OWNER" \
    --config "user.vdm.team=$TEAM" \
    --config "user.vdm.variant=$VARIANT" \
    --config "user.vdm.policy=$POLICY" \
    --config "user.vdm.size=$SIZE" \
    --config "user.vdm.repository.trust=$REPOSITORY_TRUST" \
    --config "user.vdm.repository.allowlist=$REPOSITORY_ALLOWLIST" \
    --config "user.vdm.providers.allowlist=$PROVIDER_ALLOWLIST" \
    --config "user.vdm.session.budget_usd=$SESSION_BUDGET" \
    --config "user.vdm.session.ttl=$SESSION_TTL" \
    --config "user.vdm.workspace.lifecycle=$WORKSPACE_LIFECYCLE"
created=true
project_cmd start "$NAME"
wait_for_vm "$NAME" || die "VM agent did not become ready: $NAME"
created=false
trap - EXIT
log "Launched $NAME from $ALIAS"
