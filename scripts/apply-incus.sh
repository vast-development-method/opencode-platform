#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

for command in incus jq python3; do
    require_command "$command"
done

expected_networks=("$INCUS_BUILD_NETWORK" "$INCUS_RUNTIME_NETWORK")
expected_acls=(vdm-build)
for policy_file in "$ROOT_DIR"/incus/acls/generated/*.yaml; do
    expected_acls+=("vdm-agent-$(basename "$policy_file" .yaml)")
done

is_expected_name() {
    local wanted="${1:?name required}"
    shift
    local item
    for item in "$@"; do
        [ "$item" = "$wanted" ] && return 0
    done
    return 1
}

migrate_legacy_project_networks() {
    local feature
    local name
    local -a instances=()
    local -a networks=()
    local -a acls=()

    feature="$(incus_cmd project get "$INCUS_PROJECT" features.networks)"
    [ "$feature" = true ] || return 0

    mapfile -t instances < <(
        project_cmd list --format json |
            jq -r '.[].name'
    )
    if (("${#instances[@]}" > 0)); then
        printf 'Instances in %s:\n' "$INCUS_PROJECT" >&2
        printf '  %s\n' "${instances[@]}" >&2
        die "The legacy project owns its networks. Automatic migration is safe only before instances exist. Export or remove these instances deliberately, then rerun apply-incus.sh."
    fi

    mapfile -t networks < <(
        project_cmd network list --format json |
            jq -r '.[].name'
    )
    for name in "${networks[@]}"; do
        is_expected_name "$name" "${expected_networks[@]}" ||
            die "Refusing to migrate project $INCUS_PROJECT because it owns an unrelated network: $name"
    done

    mapfile -t acls < <(
        project_cmd network acl list --format json |
            jq -r '.[].name'
    )
    for name in "${acls[@]}"; do
        is_expected_name "$name" "${expected_acls[@]}" ||
            die "Refusing to migrate project $INCUS_PROJECT because it owns an unrelated ACL: $name"
    done

    log "Migrating legacy project-owned VDM networks to host-managed bridges"
    for policy_file in "$ROOT_DIR"/incus/profiles/generated/policies/*.yaml; do
        name="vdm-policy-$(basename "$policy_file" .yaml)"
        project_cmd profile delete "$name" >/dev/null 2>&1 || true
    done
    for name in "${expected_networks[@]}"; do
        project_cmd network delete "$name" >/dev/null 2>&1 || true
    done
    for name in "${expected_acls[@]}"; do
        project_cmd network acl delete "$name" >/dev/null 2>&1 || true
    done
    incus_cmd project set "$INCUS_PROJECT" features.networks=false
}

if ! incus_cmd project show "$INCUS_PROJECT" >/dev/null 2>&1; then
    log "Creating Incus project $INCUS_PROJECT"
    incus_cmd project create "$INCUS_PROJECT" \
        --config features.images=true \
        --config features.networks=false \
        --config features.profiles=true \
        --config features.storage.volumes=true
else
    migrate_legacy_project_networks
fi

incus_cmd project edit "$INCUS_PROJECT" < "$ROOT_DIR/incus/projects/vdm-agents.yaml"
[ "$(incus_cmd project get "$INCUS_PROJECT" features.networks)" = false ] ||
    die "Project $INCUS_PROJECT must share host-managed networks (features.networks=false)."

check_subnet_available() {
    local network="${1:?network required}"
    local subnet="${2:?subnet required}"
    local routes_json

    default_cmd network show "$network" >/dev/null 2>&1 && return 0
    command -v ip >/dev/null 2>&1 || return 0
    routes_json="$(ip -j -4 route show)"

    if ! python3 - "$network" "$subnet" "$routes_json" <<'PY'
import ipaddress
import json
import sys

network_name = sys.argv[1]
wanted = ipaddress.ip_network(sys.argv[2])
routes = json.loads(sys.argv[3])
for route in routes:
    destination = route.get("dst")
    if not destination or destination == "default":
        continue
    try:
        current = ipaddress.ip_network(destination, strict=False)
    except ValueError:
        continue
    if current.overlaps(wanted) and route.get("dev") != network_name:
        print(
            f"{wanted} overlaps host route {destination} "
            f"on {route.get('dev', 'unknown')}",
            file=sys.stderr,
        )
        raise SystemExit(1)
PY
    then
        die "Refusing to create $network because its subnet conflicts with an existing host route."
    fi
}

assert_managed_default_resource() {
    local kind="${1:?resource kind required}"
    local name="${2:?resource name required}"
    local marker

    case "$kind" in
        network)
            marker="$(default_cmd network get "$name" user.vdm.platform 2>/dev/null || true)"
            ;;
        acl)
            marker="$(default_cmd network acl get "$name" user.vdm.platform 2>/dev/null || true)"
            ;;
        *) die "Unknown resource kind: $kind" ;;
    esac
    [ "$marker" = "$PLATFORM_NAME" ] ||
        die "Refusing to overwrite existing default-project $kind $name because it is not marked as managed by $PLATFORM_NAME."
}

apply_network() {
    local name="$1"
    local file="$2"
    local subnet="$3"

    if default_cmd network show "$name" >/dev/null 2>&1; then
        assert_managed_default_resource network "$name"
    else
        check_subnet_available "$name" "$subnet"
        default_cmd network create "$name" --type=bridge \
            user.vdm.managed=true \
            "user.vdm.platform=$PLATFORM_NAME"
    fi
    default_cmd network edit "$name" < "$file"
}

apply_acl() {
    local name="$1"
    local file="$2"

    if default_cmd network acl show "$name" >/dev/null 2>&1; then
        assert_managed_default_resource acl "$name"
    else
        default_cmd network acl create "$name" \
            user.vdm.managed=true \
            "user.vdm.platform=$PLATFORM_NAME"
    fi
    default_cmd network acl edit "$name" < "$file"
}

apply_network \
    "$INCUS_BUILD_NETWORK" \
    "$ROOT_DIR/incus/networks/vdm-buildbr0.yaml" \
    10.248.17.0/24
apply_network \
    "$INCUS_RUNTIME_NETWORK" \
    "$ROOT_DIR/incus/networks/vdm-agentbr0.yaml" \
    10.248.18.0/24

apply_acl vdm-build "$ROOT_DIR/incus/acls/vdm-build.yaml"
for policy_file in "$ROOT_DIR"/incus/acls/generated/*.yaml; do
    policy="$(basename "$policy_file" .yaml)"
    apply_acl "vdm-agent-$policy" "$policy_file"
done

apply_profile() {
    local profile="$1"
    local profile_file="$2"

    if ! project_cmd profile show "$profile" >/dev/null 2>&1; then
        project_cmd profile create "$profile"
    fi

    if [ -n "${INCUS_STORAGE_POOL:-}" ]; then
        [[ "$INCUS_STORAGE_POOL" =~ ^[A-Za-z0-9_.-]+$ ]] ||
            die "Unsafe Incus storage pool name: $INCUS_STORAGE_POOL"
        sed "s/pool: default/pool: ${INCUS_STORAGE_POOL}/" "$profile_file" |
            project_cmd profile edit "$profile"
    else
        project_cmd profile edit "$profile" < "$profile_file"
    fi
}

for profile_file in "$ROOT_DIR"/incus/profiles/generated/images/*.yaml; do
    name="$(basename "$profile_file" .yaml)"
    apply_profile "vdm-opencode-$name" "$profile_file"
done
for profile_file in "$ROOT_DIR"/incus/profiles/generated/sizes/*.yaml; do
    name="$(basename "$profile_file" .yaml)"
    apply_profile "vdm-size-$name" "$profile_file"
done
for profile_file in "$ROOT_DIR"/incus/profiles/generated/policies/*.yaml; do
    name="$(basename "$profile_file" .yaml)"
    apply_profile "vdm-policy-$name" "$profile_file"
done

default_cmd network show "$INCUS_BUILD_NETWORK" >/dev/null
default_cmd network show "$INCUS_RUNTIME_NETWORK" >/dev/null
default_cmd network acl show vdm-build >/dev/null

log "Incus project, host-managed bridge networks, ACLs and profiles applied"
