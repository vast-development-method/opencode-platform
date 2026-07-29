#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/build-resources.sh"

VARIANT=""
CLEAN_BUILD=false
USE_CACHE="${VDM_BUILD_CACHE:-true}"

while (($# > 0)); do
    case "$1" in
        --clean)
            CLEAN_BUILD=true
            ;;
        --no-cache)
            USE_CACHE=false
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "Unknown build option: $1"
            ;;
        *)
            [ -z "$VARIANT" ] || die "Only one build variant may be specified."
            VARIANT="$1"
            ;;
    esac
    shift
done
(($# == 0)) || die "Unexpected build arguments: $*"

case "${USE_CACHE,,}" in
    true|1|yes) USE_CACHE=true ;;
    false|0|no) USE_CACHE=false ;;
    *) die "VDM_BUILD_CACHE must be true or false." ;;
esac

variant_exists "$VARIANT" ||
    die "Usage: $0 [--clean] [--no-cache] {${PLATFORM_IMAGES[*]}}"

for command in incus jq sha256sum tar; do
    require_command "$command"
done
[ "$(uname -s)" = Linux ] || die "Image builds require a Linux host."
if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    die "Image builds require read/write access to /dev/kvm."
fi
incus_cmd info >/dev/null 2>&1 ||
    die "The build user cannot communicate with the Incus daemon."

storage_pool="${INCUS_STORAGE_POOL:-default}"
incus_cmd storage show "$storage_pool" >/dev/null 2>&1 ||
    die "Incus storage pool not found: $storage_pool"

select_build_resources "$VARIANT" "$storage_pool" "$USE_CACHE"
print_build_resource_plan "$VARIANT"

"$SCRIPT_DIR/apply-incus.sh"

build_fingerprint="$(
    cd "$ROOT_DIR"
    {
        printf '%s\n' \
            "$PLATFORM_VERSION" \
            "$VARIANT" \
            "${PLATFORM_IMAGE_COMPONENTS[$VARIANT]}" \
            "$BUILD_SELECTED_DISK"
        while IFS= read -r -d '' path; do
            sha256sum "$path"
        done < <(
            find \
                image/files \
                image/provision \
                -type f \
                -print0 |
                sort -z
        )
        sha256sum \
            manifest/generated/platform.env \
            manifest/platform.env \
            manifest/toolchain.env \
            scripts/build-image.sh \
            scripts/lib/build-resources.sh \
            scripts/verify-image.sh
    } | sha256sum | awk '{print $1}'
)"
BUILD_NAME="vdm-build-${VARIANT}-${build_fingerprint:0:12}"
ALIAS="$(image_alias "$VARIANT")"
BUILD_SUCCESS=false
CACHE_DEVICE=build-cache
DIAGNOSTIC_DIR=""

instance_exists() {
    project_cmd info "$BUILD_NAME" >/dev/null 2>&1
}

instance_status() {
    project_cmd list "$BUILD_NAME" --format json |
        jq -r '.[0].status // "Unknown"'
}

assert_managed_checkpoint() {
    local managed
    local fingerprint
    local variant

    managed="$(
        project_cmd config get "$BUILD_NAME" user.vdm.build.managed 2>/dev/null ||
            true
    )"
    fingerprint="$(
        project_cmd config get "$BUILD_NAME" user.vdm.build.fingerprint 2>/dev/null ||
            true
    )"
    variant="$(
        project_cmd config get "$BUILD_NAME" user.vdm.build.variant 2>/dev/null ||
            true
    )"
    if [ "$managed" = true ] &&
        [ "$fingerprint" = "$build_fingerprint" ] &&
        [ "$variant" = "$VARIANT" ]; then
        return
    fi
    die "Refusing to reuse or delete $BUILD_NAME because its build ownership metadata is invalid."
}

device_exists() {
    project_cmd config device get "$BUILD_NAME" "$CACHE_DEVICE" source \
        >/dev/null 2>&1
}

detach_cache() {
    device_exists || return 0
    project_cmd config device remove "$BUILD_NAME" "$CACHE_DEVICE"
}

stop_checkpoint() {
    local status

    instance_exists || return 0
    status="$(instance_status 2>/dev/null || true)"
    [ "$status" = Running ] || return 0
    project_cmd stop "$BUILD_NAME" --timeout 60 >/dev/null 2>&1 ||
        project_cmd stop "$BUILD_NAME" --force >/dev/null 2>&1 ||
        true
}

collect_failure_diagnostics() {
    local timestamp

    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    DIAGNOSTIC_DIR="$ROOT_DIR/build/diagnostics/${BUILD_NAME}-${timestamp}"
    install -d -m 0750 "$DIAGNOSTIC_DIR"

    {
        printf 'variant=%s\n' "$VARIANT"
        printf 'build_name=%s\n' "$BUILD_NAME"
        printf 'fingerprint=%s\n' "$build_fingerprint"
        printf 'selected_cpus=%s\n' "$BUILD_SELECTED_CPUS"
        printf 'selected_memory=%s\n' "$BUILD_SELECTED_MEMORY"
        printf 'selected_disk=%s\n' "$BUILD_SELECTED_DISK"
        printf 'host_memory_available_mib=%s\n' "$BUILD_HOST_AVAILABLE_MIB"
        printf 'host_memory_reserve_mib=%s\n' "$BUILD_HOST_RESERVE_MIB"
        printf 'cache_enabled=%s\n' "$USE_CACHE"
    } > "$DIAGNOSTIC_DIR/build-plan.env"

    incus_cmd version > "$DIAGNOSTIC_DIR/incus-version.txt" 2>&1 || true
    project_cmd info "$BUILD_NAME" > "$DIAGNOSTIC_DIR/instance-info.txt" 2>&1 ||
        true
    project_cmd config show "$BUILD_NAME" --expanded \
        > "$DIAGNOSTIC_DIR/instance-config.yaml" 2>&1 ||
        true
    project_cmd console "$BUILD_NAME" --show-log \
        > "$DIAGNOSTIC_DIR/console.log" 2>&1 ||
        true
    free -h > "$DIAGNOSTIC_DIR/host-memory.txt" 2>&1 || true
    df -hT > "$DIAGNOSTIC_DIR/host-filesystems.txt" 2>&1 || true
    journalctl --kernel --boot -n 200 --no-pager \
        > "$DIAGNOSTIC_DIR/kernel.log" 2>&1 ||
        true
}

finish() {
    local status=$?

    trap - EXIT INT TERM
    set +e
    if [ "$BUILD_SUCCESS" = true ]; then
        stop_checkpoint
        detach_cache
        project_cmd delete "$BUILD_NAME" --force >/dev/null 2>&1
    elif instance_exists; then
        collect_failure_diagnostics
        stop_checkpoint
        detach_cache
        warn "Build failed. The stopped checkpoint was retained as $BUILD_NAME."
        warn "Rerun the same command to resume completed stages."
        [ -z "$DIAGNOSTIC_DIR" ] ||
            warn "Diagnostics: $DIAGNOSTIC_DIR"
    fi
    exit "$status"
}
trap finish EXIT
trap 'exit 130' INT TERM

if instance_exists; then
    assert_managed_checkpoint
    if [ "$CLEAN_BUILD" = true ]; then
        log "Discarding requested clean-build checkpoint $BUILD_NAME"
        stop_checkpoint
        detach_cache
        project_cmd delete "$BUILD_NAME" --force
    fi
fi

if ! instance_exists; then
    log "Creating build VM $BUILD_NAME"
    project_cmd init "$INCUS_BASE_IMAGE" "$BUILD_NAME" --vm \
        --profile "vdm-opencode-${VARIANT}" \
        --profile "vdm-policy-${PLATFORM_IMAGE_DEFAULT_POLICY[$VARIANT]}" \
        --storage "$storage_pool" \
        --config "limits.cpu=$BUILD_SELECTED_CPUS" \
        --config "limits.memory=$BUILD_SELECTED_MEMORY" \
        --device "root,size=$BUILD_SELECTED_DISK"

    project_cmd config set "$BUILD_NAME" user.vdm.build.managed true
    project_cmd config set "$BUILD_NAME" user.vdm.build.variant "$VARIANT"
    project_cmd config set "$BUILD_NAME" \
        user.vdm.build.fingerprint "$build_fingerprint"
    project_cmd config set "$BUILD_NAME" user.vdm.build.state provisioning
    project_cmd config set "$BUILD_NAME" user.vdm.build.cache "$USE_CACHE"

    # Builders use the dedicated build bridge. Runtime policy remains attached
    # to the published image only through launch-time profiles.
    project_cmd config device override "$BUILD_NAME" eth0 \
        network="$INCUS_BUILD_NETWORK" \
        name=eth0 \
        security.acls=vdm-build \
        security.acls.default.ingress.action=reject \
        security.acls.default.egress.action=reject \
        security.ipv4_filtering=true
else
    log "Resuming retained build checkpoint $BUILD_NAME"
    stop_checkpoint
    project_cmd config set "$BUILD_NAME" limits.cpu "$BUILD_SELECTED_CPUS"
    project_cmd config set "$BUILD_NAME" limits.memory "$BUILD_SELECTED_MEMORY"
fi

build_state="$(
    project_cmd config get "$BUILD_NAME" user.vdm.build.state 2>/dev/null ||
        true
)"
case "$build_state" in
    provisioning|finalized) ;;
    *) die "Invalid retained build state on $BUILD_NAME: ${build_state:-missing}" ;;
esac

ensure_cache_volume() {
    local marker

    if project_cmd storage volume show \
        "$storage_pool" "$PLATFORM_BUILD_CACHE_VOLUME" >/dev/null 2>&1; then
        marker="$(
            project_cmd storage volume get \
                "$storage_pool" "$PLATFORM_BUILD_CACHE_VOLUME" \
                user.vdm.platform 2>/dev/null ||
                true
        )"
        [ "$marker" = "$PLATFORM_NAME" ] ||
            die "Refusing to use existing volume $PLATFORM_BUILD_CACHE_VOLUME because it is not marked as managed by $PLATFORM_NAME."
    else
        project_cmd storage volume create \
            "$storage_pool" "$PLATFORM_BUILD_CACHE_VOLUME" \
            "size=${PLATFORM_BUILD_CACHE_SIZE_GIB}GiB" \
            user.vdm.managed=true \
            "user.vdm.platform=$PLATFORM_NAME"
    fi
}

attach_cache() {
    ensure_cache_volume
    if device_exists; then
        [ "$(
            project_cmd config device get \
                "$BUILD_NAME" "$CACHE_DEVICE" source
        )" = "$PLATFORM_BUILD_CACHE_VOLUME" ] ||
            die "Unexpected cache device source on $BUILD_NAME."
        return
    fi
    project_cmd config device add \
        "$BUILD_NAME" "$CACHE_DEVICE" disk \
        "pool=$storage_pool" \
        "source=$PLATFORM_BUILD_CACHE_VOLUME" \
        path=/var/cache/vdm-build
}

if [ "$build_state" = provisioning ] && [ "$USE_CACHE" = true ]; then
    attach_cache
fi

project_cmd start "$BUILD_NAME"
wait_for_vm "$BUILD_NAME" || die "VM agent did not become ready: $BUILD_NAME"

COMMON_ENV=(
    "AGENT_USER=$AGENT_USER"
    "NODE_MAJOR=$NODE_MAJOR"
    "NODESOURCE_SETUP_SHA256=$NODESOURCE_SETUP_SHA256"
    "OPENCODE_PACKAGE=$OPENCODE_PACKAGE"
    "OPENCODE_EXPECTED_VERSION=$OPENCODE_EXPECTED_VERSION"
    "GIT_MCP_PACKAGE=$GIT_MCP_PACKAGE"
    "GIT_MCP_EXPECTED_VERSION=$GIT_MCP_EXPECTED_VERSION"
    "JOOMLA_MCP_PACKAGE=$JOOMLA_MCP_PACKAGE"
    "JOOMLA_MCP_EXPECTED_VERSION=$JOOMLA_MCP_EXPECTED_VERSION"
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
if [ "$USE_CACHE" = true ]; then
    COMMON_ENV+=(
        VDM_BUILD_CACHE_DIR=/var/cache/vdm-build
        NPM_CONFIG_CACHE=/var/cache/vdm-build/npm
        PIP_CACHE_DIR=/var/cache/vdm-build/pip
    )
fi

exec_with_env() {
    local args=()
    local item
    for item in "${COMMON_ENV[@]}"; do
        args+=(--env "$item")
    done
    project_cmd exec "$BUILD_NAME" "${args[@]}" -- "$@"
}

stage_complete() {
    local stage="${1:?stage required}"
    project_cmd exec "$BUILD_NAME" -- \
        test -f "/var/lib/vdm-opencode-build/stages/${stage}.done"
}

mark_stage_complete() {
    local stage="${1:?stage required}"
    project_cmd exec "$BUILD_NAME" -- \
        install -D -o root -g root -m 0644 /dev/null \
        "/var/lib/vdm-opencode-build/stages/${stage}.done"
}

run_stage() {
    local stage="${1:?stage required}"
    local provision="${2:?provision script required}"

    if stage_complete "$stage"; then
        log "Reusing completed build stage $stage"
        return
    fi
    log "Running build stage $stage"
    exec_with_env bash "/opt/vdm-build/$provision"
    mark_stage_complete "$stage"
}

if [ "$build_state" = provisioning ]; then
    log "Uploading platform files and provisioning scripts"
    tar -C "$ROOT_DIR/image/files" -cf - . |
        project_cmd exec "$BUILD_NAME" -- tar -C / -xf -
    project_cmd exec "$BUILD_NAME" -- install -d -m 0755 /opt/vdm-build
    tar -C "$ROOT_DIR/image/provision" -cf - . |
        project_cmd exec "$BUILD_NAME" -- tar -C /opt/vdm-build -xf -

    run_stage common common.sh
    for component in ${PLATFORM_IMAGE_COMPONENTS[$VARIANT]}; do
        provision="${PLATFORM_COMPONENT_PROVISION[$component]:-}"
        [ -z "$provision" ] || run_stage "component-$component" "$provision"
    done

    project_cmd exec "$BUILD_NAME" \
        --env "PLATFORM_VERSION=$PLATFORM_VERSION" \
        --env "AGENT_USER=$AGENT_USER" \
        -- bash /opt/vdm-build/finalize.sh "$VARIANT"
    project_cmd config set "$BUILD_NAME" user.vdm.build.state finalized
fi

"$SCRIPT_DIR/verify-image.sh" "$BUILD_NAME" "$VARIANT"

log "Publishing $ALIAS directly from the verified stopped instance"
project_cmd stop "$BUILD_NAME" --timeout 60
detach_cache
project_cmd publish "$BUILD_NAME" --alias "$ALIAS" --reuse
project_cmd image set-property "$ALIAS" org.vdm.platform "$PLATFORM_NAME"
project_cmd image set-property "$ALIAS" org.vdm.version "$PLATFORM_VERSION"
project_cmd image set-property "$ALIAS" org.vdm.variant "$VARIANT"
project_cmd image set-property \
    "$ALIAS" org.vdm.architecture \
    "$(canonical_architecture "$(uname -m)")"

BUILD_SUCCESS=true
log "Published $ALIAS"
