#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

require_command incus

if ! incus_cmd project show "$INCUS_PROJECT" >/dev/null 2>&1; then
    log "Creating Incus project $INCUS_PROJECT"
    incus_cmd project create "$INCUS_PROJECT"
fi
incus_cmd project edit "$INCUS_PROJECT" < "$ROOT_DIR/incus/projects/vdm-agents.yaml"

apply_network() {
    local name="$1"
    local file="$2"
    if ! project_cmd network show "$name" >/dev/null 2>&1; then
        project_cmd network create "$name"
    fi
    project_cmd network edit "$name" < "$file"
}

apply_network "$INCUS_BUILD_NETWORK" "$ROOT_DIR/incus/networks/vdm-buildbr0.yaml"
apply_network "$INCUS_RUNTIME_NETWORK" "$ROOT_DIR/incus/networks/vdm-agentbr0.yaml"

apply_acl() {
    local name="$1"
    local file="$2"
    if ! project_cmd network acl show "$name" >/dev/null 2>&1; then
        project_cmd network acl create "$name"
    fi
    project_cmd network acl edit "$name" < "$file"
}

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
        sed "s/pool: default/pool: ${INCUS_STORAGE_POOL}/" "$profile_file" | project_cmd profile edit "$profile"
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

log "Incus project definition applied"
