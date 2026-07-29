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

project_cmd init "$ALIAS" "$NAME" --vm \
    --profile "vdm-opencode-${VARIANT}" \
    --profile "vdm-size-$SIZE" \
    --profile "vdm-policy-$POLICY"
project_cmd config set "$NAME" user.vdm.owner "${VDM_SESSION_OWNER:-$USER}"
project_cmd config set "$NAME" user.vdm.team "${VDM_SESSION_TEAM:-individual}"
project_cmd config set "$NAME" user.vdm.policy "$POLICY"
project_cmd config set "$NAME" user.vdm.size "$SIZE"
project_cmd config set "$NAME" user.vdm.repository.trust "${VDM_REPOSITORY_TRUST:-trusted}"
project_cmd config set "$NAME" user.vdm.repository.allowlist "${VDM_REPOSITORY_ALLOWLIST:-none}"
project_cmd config set "$NAME" user.vdm.providers.allowlist "${VDM_PROVIDER_ALLOWLIST:-local-default}"
project_cmd config set "$NAME" user.vdm.session.budget_usd "${VDM_SESSION_BUDGET_USD:-0}"
project_cmd config set "$NAME" user.vdm.session.ttl "${VDM_SESSION_TTL:-$DEFAULT_SESSION_TTL}"
project_cmd config set "$NAME" user.vdm.workspace.lifecycle "${VDM_WORKSPACE_LIFECYCLE:-disposable}"
project_cmd start "$NAME"
wait_for_vm "$NAME" || die "VM agent did not become ready: $NAME"
log "Launched $NAME from $ALIAS"
