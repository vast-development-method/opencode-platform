#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$ROOT_DIR/image/files/usr/local/libexec/vdm-joomla-mcp"
tmp_dir="$(mktemp -d)"
runtime_base=''
trap 'rm -rf "$tmp_dir"; [[ -z "$runtime_base" ]] || rm -rf "$runtime_base"' EXIT
chmod 0711 "$tmp_dir"
agent_dir="$tmp_dir/agent"
mkdir -m 0700 "$agent_dir"
test_user="$(id -un)"
if ((EUID == 0)); then
    test_user=nobody
    if ! chown "$test_user" "$agent_dir" 2>/dev/null; then
        # Restricted user namespaces can expose uid 0 only. Exercise fail-closed
        # behavior here; successful user switching is tested on the CI host.
        "$helper" config-check "$ROOT_DIR/image/files/etc/joomla-mcp/sites.readonly.example.json"
        printf '{"protected":true}\n' > "$agent_dir/opencode.json"
        before="$(sha256sum "$agent_dir/opencode.json")"
        if "$helper" configure "$tmp_dir/sites.json" "$agent_dir/opencode.json" company \
            https://example.com/api/index.php/v1/joomengine-mcp readonly JOOMLA_MCP_SITE_TOKEN nobody >/dev/null 2>&1; then
            printf 'Configuration proceeded after failing to drop root privileges.\n' >&2; exit 1
        fi
        [[ "$before" == "$(sha256sum "$agent_dir/opencode.json")" && ! -e "$tmp_dir/sites.json" ]]
        printf 'Native Joomla configuration fails closed when privilege drop is unavailable.\n'
        printf 'SKIP successful configure/host cases: this user namespace exposes only UID 0; CI runs them as its real non-root user.\n'
        exit 0
    fi
fi
printf '{"mcp":{"joomla":{"type":"local"},"git":{"enabled":true}}}\n' > "$agent_dir/opencode.json"
if ((EUID == 0)); then chown "$test_user" "$agent_dir/opencode.json"; fi
configure() {
    "$helper" configure "$tmp_dir/sites.json" "$agent_dir/opencode.json" "$@" "$test_user"
}
configure company https://www.example.com/joomla/api/index.php/v1/joomengine-mcp readonly JOOMLA_MCP_SITE_TOKEN
configure jcb-build https://build.example.com:8443/api/index.php/v1/joomengine-mcp write JOOMLA_MCP_JCB_BUILD_TOKEN
jq -e '.sites | length == 2' "$tmp_dir/sites.json" >/dev/null
jq -e '.mcp.git.enabled == true and .mcp.joomla == null
    and .mcp.joomla_company.type == "remote" and .mcp.joomla_company.oauth == false
    and .mcp.joomla_company.headers["X-Joomla-Token"] == "{env:JOOMLA_MCP_SITE_TOKEN}"
    and .mcp["joomla_jcb-build"].url == "https://build.example.com:8443/api/index.php/v1/joomengine-mcp"
    and .mcp["joomla_jcb-build"].enabled == true' "$agent_dir/opencode.json" >/dev/null
[[ "$(stat -c %u "$agent_dir/opencode.json")" == "$(id -u "$test_user")" ]]
for endpoint in \
    http://example.com/api/index.php/v1/joomengine-mcp \
    https://user:password@example.com/api/index.php/v1/joomengine-mcp \
    https://example.com:99999/api/index.php/v1/joomengine-mcp \
    https://example.com/../api/index.php/v1/joomengine-mcp \
    'https://example.com/api/index.php/v1/joomengine-mcp?token=secret'; do
    if configure company "$endpoint" readonly JOOMLA_MCP_SITE_TOKEN >/dev/null 2>&1; then
        printf 'Invalid endpoint was accepted: %s\n' "$endpoint" >&2; exit 1
    fi
done
before="$(sha256sum "$tmp_dir/sites.json" "$agent_dir/opencode.json")"
if configure jcb_build https://example.com/api/index.php/v1/joomengine-mcp readonly JOOMLA_MCP_JCB_BUILD_TOKEN >/dev/null 2>&1; then
    printf 'Normalized token-reference collision was accepted.\n' >&2; exit 1
fi
[[ "$before" == "$(sha256sum "$tmp_dir/sites.json" "$agent_dir/opencode.json")" ]]
configure company https://changed.example.com/api/index.php/v1/joomengine-mcp readonly JOOMLA_MCP_SITE_TOKEN
jq -e '.sites | length == 2' "$tmp_dir/sites.json" >/dev/null
# Regression: root must not follow an agent-controlled parent link into a root
# directory when reading, creating a temporary file or replacing OpenCode JSON.
as_root=()
if ((EUID == 0)) || { command -v sudo >/dev/null && sudo -n true 2>/dev/null; }; then
    if ((EUID != 0)); then as_root=(sudo -n); fi
    "${as_root[@]}" install -d -m 0755 -o root -g root "$tmp_dir/protected"
    printf '{"protected":true}\n' | "${as_root[@]}" tee "$tmp_dir/protected/opencode.json" >/dev/null
    "${as_root[@]}" chmod 0644 "$tmp_dir/protected/opencode.json"
    ln -s "$tmp_dir/protected" "$agent_dir/redirect"
    before="$(sha256sum "$tmp_dir/protected/opencode.json" "$tmp_dir/sites.json")"
    if "${as_root[@]}" "$helper" configure "$tmp_dir/sites.json" "$agent_dir/redirect/opencode.json" \
        injected https://example.com/api/index.php/v1/joomengine-mcp readonly JOOMLA_MCP_INJECTED_TOKEN "$test_user" >/dev/null 2>&1; then
        printf 'Root followed an agent-controlled parent symlink.\n' >&2; exit 1
    fi
    [[ "$before" == "$(sha256sum "$tmp_dir/protected/opencode.json" "$tmp_dir/sites.json")" ]]
    "${as_root[@]}" rm -rf "$tmp_dir/protected"
fi
printf 'Native Joomla site configuration and privilege tests passed.\n'

runtime_base="$(mktemp -d /dev/shm/joomla-native-test.XXXXXX)"
export PATH="$ROOT_DIR/tests/fixtures/joomla:$PATH"
export JOOMLA_TEST_HELPER="$helper"
export CAPTURE_CONFIG="$tmp_dir/host-sites.json" CAPTURE_OPENCODE="$agent_dir/host-opencode.json"
export VDM_RUNTIME_BASE="$runtime_base" AGENT_USER="$test_user"
printf '{"mcp":{"git":{"enabled":true}}}\n' > "$CAPTURE_OPENCODE"
if ((EUID == 0)); then chown "$test_user" "$CAPTURE_OPENCODE"; fi
"$ROOT_DIR/scripts/configure-joomla-mcp.sh" native-test https://example.com/subdir company readonly >/dev/null
"$ROOT_DIR/scripts/configure-joomla-mcp.sh" native-test https://builder.example.com/api/index.php jcb-build write >/dev/null
jq -e '.sites.company.url == "https://example.com/subdir/api/index.php/v1/joomengine-mcp"
    and .sites["jcb-build"].url == "https://builder.example.com/api/index.php/v1/joomengine-mcp"' "$CAPTURE_CONFIG" >/dev/null
[[ "$(grep -c '^JOOMLA_MCP_JCB_BUILD_TOKEN=' "$runtime_base/vdm-opencode/native-test.env")" == 1 ]]
if "$ROOT_DIR/scripts/configure-joomla-mcp.sh" native-test https://other.example.com jcb_build readonly >/dev/null 2>&1; then
    printf 'Host configuration accepted a token-reference collision.\n' >&2; exit 1
fi
printf 'Native Joomla host configuration tests passed.\n'
