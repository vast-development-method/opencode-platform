#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
NAME="${1:-}"
CONFIG="${2:-}"
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ && $# == 2 ]] ||
    die "Usage: $0 INSTANCE SERVICE_NETWORK_JSON"
for dependency in python3 jq sha256sum; do require_command "$dependency"; done
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
python3 "$SCRIPT_DIR/render-service-network.py" "$CONFIG" > "$work/acl.json"
project_cmd list "$NAME" --format json | jq -e --arg name "$NAME" \
    '[.[] | select(.name == $name)] | if length == 1 then .[0] else error("instance not found") end' > "$work/instance.json"
jq -e --arg network "$INCUS_RUNTIME_NETWORK" '
  (.expanded_config["user.vdm.variant"] | type == "string" and length > 0) and
  ([.expanded_config | keys[] | select(startswith("user.ductor.") or startswith("user.crabbox."))] | length == 0) and
  .expanded_devices.eth0.type == "nic" and .expanded_devices.eth0.network == $network
' "$work/instance.json" >/dev/null ||
    die 'Only standalone platform workers on the managed runtime network can use this command; configure Ductor pools through Ductor'
fingerprint="$(sha256sum "$work/acl.json")"
acl="vdm-service-${NAME:0:30}-${fingerprint:0:16}"
jq --arg instance "$NAME" '.config["user.vdm.instance"] = $instance' "$work/acl.json" > "$work/owned.json"
if default_cmd network acl show "$acl" >/dev/null 2>&1; then
    [[ $(default_cmd network acl get "$acl" user.vdm.platform) == "$PLATFORM_NAME" &&
       $(default_cmd network acl get "$acl" user.vdm.instance) == "$NAME" ]] || die 'Existing ACL is not owned by this worker'
else
    default_cmd network acl create "$acl" "user.vdm.platform=$PLATFORM_NAME" "user.vdm.instance=$NAME"
fi
default_cmd network acl edit "$acl" < "$work/owned.json"
if jq -e '.devices.eth0 != null' "$work/instance.json" >/dev/null; then
    project_cmd config device set "$NAME" eth0 \
        "security.acls=$acl" security.acls.default.ingress.action=reject security.acls.default.egress.action=reject security.ipv4_filtering=true
else
    project_cmd config device override "$NAME" eth0 \
        "security.acls=$acl" security.acls.default.ingress.action=reject security.acls.default.egress.action=reject security.ipv4_filtering=true
fi
project_cmd config set "$NAME" "user.vdm.service-network.sha256=${fingerprint%% *}"
log "Applied exact service routes to $NAME; all other new connections are rejected"
