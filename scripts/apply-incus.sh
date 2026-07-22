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

if ! project_cmd network acl show "$INCUS_RUNTIME_ACL" >/dev/null 2>&1; then
    project_cmd network acl create "$INCUS_RUNTIME_ACL"
fi
project_cmd network acl edit "$INCUS_RUNTIME_ACL" < "$ROOT_DIR/incus/acls/vdm-agent-runtime.yaml"

for variant in base php python cpp typescript full; do
    profile="vdm-opencode-${variant}"
    if ! project_cmd profile show "$profile" >/dev/null 2>&1; then
        project_cmd profile create "$profile"
    fi

    profile_file="$ROOT_DIR/incus/profiles/${variant}.yaml"
    if [ -n "${INCUS_STORAGE_POOL:-}" ]; then
        sed "s/pool: default/pool: ${INCUS_STORAGE_POOL}/" "$profile_file" | project_cmd profile edit "$profile"
    else
        project_cmd profile edit "$profile" < "$profile_file"
    fi
done

log "Incus project definition applied"
