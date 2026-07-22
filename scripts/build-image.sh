#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

VARIANT="${1:-}"
variant_exists "$VARIANT" || die "Variant must be one of: ${PLATFORM_IMAGES[*]}"

"$SCRIPT_DIR/apply-incus.sh"

BUILD_NAME="vdm-build-${VARIANT}-$(date +%Y%m%d%H%M%S)"
ALIAS="$(image_alias "$VARIANT")"

cleanup() {
    project_cmd delete "$BUILD_NAME" --force >/dev/null 2>&1 || true
}
trap cleanup EXIT

log "Creating build VM $BUILD_NAME"
project_cmd init "$INCUS_BASE_IMAGE" "$BUILD_NAME" --vm \
    --profile "vdm-opencode-${VARIANT}" \
    --profile "vdm-size-${PLATFORM_IMAGE_DEFAULT_SIZE[$VARIANT]}" \
    --profile "vdm-policy-${PLATFORM_IMAGE_DEFAULT_POLICY[$VARIANT]}"

# Builders need the broader build network. Replace the profile NIC for this temporary VM.
project_cmd config device override "$BUILD_NAME" eth0 \
    network="$INCUS_BUILD_NETWORK" \
    name=eth0 \
    security.acls=vdm-build \
    security.acls.default.ingress.action=reject \
    security.acls.default.egress.action=reject \
    security.ipv4_filtering=true
project_cmd start "$BUILD_NAME"
wait_for_vm "$BUILD_NAME" || die "VM agent did not become ready: $BUILD_NAME"

log "Uploading platform files and provisioning scripts"
tar -C "$ROOT_DIR/image/files" -cf - . | project_cmd exec "$BUILD_NAME" -- tar -C / -xf -
project_cmd exec "$BUILD_NAME" -- install -d -m 0755 /opt/vdm-build
tar -C "$ROOT_DIR/image/provision" -cf - . | project_cmd exec "$BUILD_NAME" -- tar -C /opt/vdm-build -xf -

COMMON_ENV=(
    "AGENT_USER=$AGENT_USER"
    "NODE_MAJOR=$NODE_MAJOR"
    "NODESOURCE_SETUP_SHA256=$NODESOURCE_SETUP_SHA256"
    "OPENCODE_PACKAGE=$OPENCODE_PACKAGE"
    "OPENCODE_EXPECTED_VERSION=$OPENCODE_EXPECTED_VERSION"
    "GIT_MCP_PACKAGE=$GIT_MCP_PACKAGE"
    "GIT_MCP_EXPECTED_VERSION=$GIT_MCP_EXPECTED_VERSION"
    "PLAYWRIGHT_MCP_PACKAGE=$PLAYWRIGHT_MCP_PACKAGE"
    "PLAYWRIGHT_MCP_EXPECTED_VERSION=$PLAYWRIGHT_MCP_EXPECTED_VERSION"
    "PLAYWRIGHT_PACKAGE=$PLAYWRIGHT_PACKAGE"
    "PLAYWRIGHT_EXPECTED_VERSION=$PLAYWRIGHT_EXPECTED_VERSION"
    "TYPESCRIPT_PACKAGE=$TYPESCRIPT_PACKAGE"
    "TYPESCRIPT_EXPECTED_VERSION=$TYPESCRIPT_EXPECTED_VERSION"
    "TSX_PACKAGE=$TSX_PACKAGE"
    "TSX_EXPECTED_VERSION=$TSX_EXPECTED_VERSION"
    "RUFF_PACKAGE=$RUFF_PACKAGE"
    "RUFF_EXPECTED_VERSION=$RUFF_EXPECTED_VERSION"
    "MYPY_PACKAGE=$MYPY_PACKAGE"
    "MYPY_EXPECTED_VERSION=$MYPY_EXPECTED_VERSION"
)

exec_with_env() {
    local args=()
    local item
    for item in "${COMMON_ENV[@]}"; do
        args+=(--env "$item")
    done
    project_cmd exec "$BUILD_NAME" "${args[@]}" -- "$@"
}

exec_with_env bash /opt/vdm-build/common.sh
for component in ${PLATFORM_IMAGE_COMPONENTS[$VARIANT]}; do
    provision="${PLATFORM_COMPONENT_PROVISION[$component]:-}"
    [[ -z "$provision" ]] || exec_with_env bash "/opt/vdm-build/$provision"
done

project_cmd exec "$BUILD_NAME" \
    --env "PLATFORM_VERSION=$PLATFORM_VERSION" \
    --env "AGENT_USER=$AGENT_USER" \
    -- bash /opt/vdm-build/finalize.sh "$VARIANT"

"$SCRIPT_DIR/verify-image.sh" "$BUILD_NAME" "$VARIANT"

log "Publishing $ALIAS"
project_cmd stop "$BUILD_NAME" --timeout 60
project_cmd snapshot create "$BUILD_NAME" sanitized
project_cmd publish "$BUILD_NAME/sanitized" --alias "$ALIAS" --reuse
project_cmd image set-property "$ALIAS" org.vdm.platform "$PLATFORM_NAME"
project_cmd image set-property "$ALIAS" org.vdm.version "$PLATFORM_VERSION"
project_cmd image set-property "$ALIAS" org.vdm.variant "$VARIANT"
project_cmd image set-property "$ALIAS" org.vdm.architecture "$(canonical_architecture)"

log "Published $ALIAS"
