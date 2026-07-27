#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$ROOT_DIR/manifest/toolchain.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/manifest/generated/platform.env"

[ "$JOOMLA_MCP_PACKAGE" = "@joomengine/joomla-mcp@0.7.0" ]
[ "$JOOMLA_MCP_EXPECTED_VERSION" = "0.7.0" ]
[[ " ${PLATFORM_IMAGE_COMPONENTS[php]} " == *" joomla-mcp "* ]]
[[ " ${PLATFORM_IMAGE_COMPONENTS[full]} " == *" joomla-mcp "* ]]
for image in base python cpp typescript; do
    [[ " ${PLATFORM_IMAGE_COMPONENTS[$image]} " != *" joomla-mcp "* ]]
done
[ "${PLATFORM_COMPONENT_PROVISION[joomla-mcp]}" = "joomla-mcp.sh" ]

example="$ROOT_DIR/image/files/etc/joomla-mcp/sites.readonly.example.json"
jq -e '
  (.sites[].api.baseUrl | startswith("https://"))
  and (.sites[].api.tokenEnv == "JOOMLA_MCP_SITE_TOKEN")
  and ([.sites[].toolsets[]
        | select(test("(\\.write$|\\.admin$|^core-update$)"))]
       | length == 0)
  and (has("approval") | not)
' "$example" >/dev/null
test ! -e "$ROOT_DIR/image/files/etc/joomla-mcp/sites.json"

provision="$ROOT_DIR/image/provision/joomla-mcp.sh"
grep -F 'npm install --global --ignore-scripts' "$provision" >/dev/null
grep -F '"enabled": false' "$provision" >/dev/null
grep -F '/usr/local/bin/vdm-joomla-mcp-config-check' "$provision" >/dev/null

for script in \
    "$ROOT_DIR/scripts/lib/runtime-credentials.sh" \
    "$ROOT_DIR/image/files/usr/local/libexec/vdm-opencode-session"; do
    grep -F 'JOOMLA_MCP_SITE_TOKEN' "$script" >/dev/null
    grep -F 'JOOMLA_MCP_UPDATE_TOKEN' "$script" >/dev/null
    grep -F 'JOOMLA_MCP_APPROVAL_SECRET' "$script" >/dev/null
done

grep -F 'allowIndefinite: false' "$ROOT_DIR/scripts/configure-joomla-mcp.sh" >/dev/null
grep -F -- '--profile read' \
    "$ROOT_DIR/image/files/usr/local/libexec/vdm-opencode-session" >/dev/null
if grep -Eq -- '--confirm-mutations|--disposable|--profile (crud|full)' \
    "$ROOT_DIR/image/files/usr/local/libexec/vdm-opencode-session"; then
    printf 'The built-in Joomla smoke test must remain non-mutating.\n' >&2
    exit 1
fi

python3 - "$ROOT_DIR/manifest/sources.lock.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as stream:
    lock = yaml.safe_load(stream)
source = lock["sources"]["joomla_mcp"]
assert source["repository"] == "https://github.com/joomengine/joomla-mcp"
assert source["inspected_ref"] == "7160096413dc71ed699e4f8e4988e4c7edc8c9e4"
assert source["package"] == "@joomengine/joomla-mcp"
assert str(source["build_ref"]) == "0.7.0"
PY

printf 'Joomla MCP integration tests passed.\n'
