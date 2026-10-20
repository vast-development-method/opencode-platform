#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d /dev/shm/vdm-platform-test-XXXXXXXX)"
agent_work="$(mktemp -d /dev/shm/vdm-platform-agent-XXXXXXXX)"
cleanup() {
    if ((EUID == 0)); then chown -R "$(id -u):$(id -g)" "$agent_work"; fi
    rm -rf -- "$work" "$agent_work"
}
trap cleanup EXIT
chmod 0700 "$work"
mkdir "$work/state"
export PLATFORM_TEST_STATE="$work/state" PLATFORM_TEST_ROOT="$ROOT" PLATFORM_TEST_INSTANCE=worker
export VDM_RUNTIME_BASE="$work" PATH="$ROOT/tests/fixtures/platform:$PATH"
PLATFORM_TEST_AGENT="$(id -un)"
export PLATFORM_TEST_AGENT PLATFORM_TEST_OPENCODE="$agent_work/opencode.json"
printf '%s\n' '{"mcp":{"git":{"enabled":true}},"instructions":["/etc/company/standards.md"]}' > "$PLATFORM_TEST_OPENCODE"
import_supported=true
if ((EUID == 0)); then
    PLATFORM_TEST_AGENT=nobody
    if ! chown -R nobody "$agent_work" 2>/dev/null; then import_supported=false; fi
fi
ln -s "$PLATFORM_TEST_OPENCODE" "$work/state/opencode.json"

reset_instance() {
    printf '%s\n' '[{"name":"worker","expanded_config":{"user.vdm.variant":"php"},"devices":{},"expanded_devices":{"eth0":{"type":"nic","network":"vdm-agentbr0","name":"eth0","mtu":"1450","security.acls":"vdm-agent-connected"}}}]' > "$work/state/instance.json"
    : > "$work/state/calls.jsonl"
}
expect_failure() {
    if "$@" > "$work/failure.log" 2>&1; then
        printf 'Expected refusal: %s\n' "$1" >&2
        exit 1
    fi
}

reset_instance
cat > "$work/routes.json" <<'JSON'
{"schema":1,"dns":["10.248.18.1"],"services":[{"name":"joomengine","address":"10.40.0.8","port":443}],"ssh_sources":["10.40.0.4"]}
JSON
"$ROOT/scripts/configure-service-network.sh" worker "$work/routes.json" > "$work/network.log"
acl="$(jq -r '.[0].devices.eth0["security.acls"]' "$work/state/instance.json")"
jq -e '.config["user.vdm.instance"] == "worker"
  and (.egress | length == 3)
  and any(.egress[]; .destination == "10.40.0.8/32" and .destination_port == "443" and .protocol == "tcp")
  and (.ingress | length == 1)
  and .ingress[0].source == "10.40.0.4/32" and .ingress[0].destination_port == "22"' "$work/state/acls/$acl.json" >/dev/null
jq -e '.[0].devices.eth0.mtu == "1450" and .[0].devices.eth0.network == "vdm-agentbr0"
  and .[0].devices.eth0["security.acls.default.egress.action"] == "reject"
  and .[0].devices.eth0["security.acls.default.ingress.action"] == "reject"
  and (.[0].expanded_config["user.vdm.service-network.sha256"] | test("^[a-f0-9]{64}$"))' "$work/state/instance.json" >/dev/null
grep -q '"override"' "$work/state/calls.jsonl"
"$ROOT/scripts/configure-service-network.sh" worker "$work/routes.json" > "$work/network.log"
grep -q '"set","worker","eth0"' "$work/state/calls.jsonl"
[[ $(find "$work/state/acls" -name '*.json' | wc -l) == 1 ]]

# A second controller may reuse its own ACL, but may not adopt an unrelated one.
jq '.config["user.vdm.instance"]="someone-else"' "$work/state/acls/$acl.json" > "$work/acl.new"
mv "$work/acl.new" "$work/state/acls/$acl.json"
expect_failure "$ROOT/scripts/configure-service-network.sh" worker "$work/routes.json"
rm -rf "$work/state/acls"

for owner in user.ductor.pool user.crabbox.pool; do
    reset_instance
    jq --arg owner "$owner" '.[0].expanded_config[$owner]="protected"' "$work/state/instance.json" > "$work/instance.new"
    mv "$work/instance.new" "$work/state/instance.json"
    expect_failure "$ROOT/scripts/configure-service-network.sh" worker "$work/routes.json"
    if grep -q '"network","acl","create"' "$work/state/calls.jsonl"; then
        printf 'Protected worker network was modified.\n' >&2; exit 1
    fi
done
reset_instance
jq '.[0].expanded_devices.eth0.network="other-network"' "$work/state/instance.json" > "$work/instance.new"
mv "$work/instance.new" "$work/state/instance.json"
expect_failure "$ROOT/scripts/configure-service-network.sh" worker "$work/routes.json"
reset_instance
PLATFORM_TEST_DEVICE_FAIL=true expect_failure "$ROOT/scripts/configure-service-network.sh" worker "$work/routes.json"
jq -e '.[0].expanded_config["user.vdm.service-network.sha256"] == null and .[0].devices.eth0 == null' "$work/state/instance.json" >/dev/null
printf 'Private service command ownership, exact routes and failure isolation passed.\n'
if [[ "$import_supported" != true ]]; then
    printf 'SKIP client import: this root-only UID namespace cannot create an unprivileged guest account; ordinary CI users run this case.\n'
    exit 0
fi

# Import the actual Ductor client shape; preserve identity and other runtime keys.
jq -n '{schema:1,url:"https://joomengine.example.test/subdir/api/index.php/v1/joomengine-mcp",alias:"joomengine-main",write_enabled:true,token:"test-joomla-dedicated-token"}' > "$work/client.json"
chmod 0600 "$work/client.json"
"$ROOT/scripts/import-joomla-credentials.sh" worker "$work/client.json" > "$work/import.log"
runtime="$work/vdm-opencode/worker.env"
grep -q '^JOOMLA_MCP_JOOMENGINE_MAIN_TOKEN=test-joomla-dedicated-token$' "$runtime"
[[ $(stat -c '%u:%a:%h' "$runtime") == "$UID:600:1" ]]
jq -e '.sites["joomengine-main"].url == "https://joomengine.example.test/subdir/api/index.php/v1/joomengine-mcp"
  and .sites["joomengine-main"].tokenEnv == "JOOMLA_MCP_JOOMENGINE_MAIN_TOKEN"
  and .sites["joomengine-main"].access == "write"' "$work/state/sites.json" >/dev/null
jq -e '.mcp["joomla_joomengine-main"].headers["X-Joomla-Token"] == "{env:JOOMLA_MCP_JOOMENGINE_MAIN_TOKEN}"
  and .mcp.git.enabled == true and .instructions == ["/etc/company/standards.md"]' "$work/state/opencode.json" >/dev/null
if grep -q 'test-joomla-dedicated-token' "$work/state/calls.jsonl" "$work/import.log"; then
    printf 'A Joomla token entered arguments or logs.\n' >&2; exit 1
fi

printf 'GITEA_MCP_TOKEN=preserved-service-identity\n' > "$work/retained.env"
awk '!/^GITEA_MCP_TOKEN=/' "$runtime" >> "$work/retained.env"
cat "$work/retained.env" > "$runtime"
"$ROOT/scripts/import-joomla-credentials.sh" worker "$work/client.json" > "$work/import.log"
grep -q '^GITEA_MCP_TOKEN=preserved-service-identity$' "$runtime"
[[ $(grep -c '^JOOMLA_MCP_JOOMENGINE_MAIN_TOKEN=' "$runtime") == 1 ]]

# An underscore alias must not share a token reference with the hyphen alias.
before="$(sha256sum "$runtime" "$work/state/sites.json" "$work/state/opencode.json")"
jq '.alias="joomengine_main"' "$work/client.json" > "$work/collision.json"
chmod 0600 "$work/collision.json"
expect_failure "$ROOT/scripts/import-joomla-credentials.sh" worker "$work/collision.json"
[[ $(sha256sum "$runtime" "$work/state/sites.json" "$work/state/opencode.json") == "$before" ]]

chmod 0644 "$work/client.json"
expect_failure "$ROOT/scripts/import-joomla-credentials.sh" worker "$work/client.json"
chmod 0600 "$work/client.json"
ln -s "$work/client.json" "$work/link.json"
expect_failure "$ROOT/scripts/import-joomla-credentials.sh" worker "$work/link.json"
jq '.token="first\nGITHUB_MCP_TOKEN=injected"' "$work/client.json" > "$work/multiline.json"
chmod 0600 "$work/multiline.json"
expect_failure "$ROOT/scripts/import-joomla-credentials.sh" worker "$work/multiline.json"
[[ $(sha256sum "$runtime" "$work/state/sites.json" "$work/state/opencode.json") == "$before" ]]
printf 'Ductor client import, alias identity, scoped tokens and private permissions passed.\n'
