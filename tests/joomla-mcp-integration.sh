#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/manifest/generated/platform.env"
for image in base php python cpp typescript full; do
    [[ " ${PLATFORM_IMAGE_COMPONENTS[$image]} " == *" joomla-mcp "* ]]
done
[ "${PLATFORM_COMPONENT_PROVISION[joomla-mcp]}" = "joomla-mcp.sh" ]
"$ROOT_DIR/image/files/usr/local/libexec/vdm-joomla-mcp" config-check \
    "$ROOT_DIR/image/files/etc/joomla-mcp/sites.readonly.example.json"
test ! -e "$ROOT_DIR/image/files/etc/joomla-mcp/sites.json"
bash "$ROOT_DIR/tests/joomla-mcp-http.sh"
printf 'Native Joomla MCP integration tests passed.\n'
