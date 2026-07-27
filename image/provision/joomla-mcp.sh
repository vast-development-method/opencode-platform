#!/usr/bin/env bash
set -Eeuo pipefail

AGENT_USER="${AGENT_USER:-opencode}"
AGENT_HOME="/home/${AGENT_USER}"

# The single-quoted program is JavaScript evaluated by Node, not shell text.
# shellcheck disable=SC2016
node -e '
const [major, minor] = process.versions.node.split(".").map(Number);
if (major < 22 || (major === 22 && minor < 12)) {
  process.stderr.write(`Joomla MCP requires Node.js 22.12 or newer; found ${process.versions.node}.\n`);
  process.exit(1);
}
'

npm install --global --ignore-scripts --no-audit --no-fund \
    "${JOOMLA_MCP_PACKAGE:?JOOMLA_MCP_PACKAGE is required}"

installed_mcp="$(
    npm list --global --json --depth=0 |
        jq -r '.dependencies["@joomengine/joomla-mcp"].version'
)"
[ "$installed_mcp" = "${JOOMLA_MCP_EXPECTED_VERSION:?JOOMLA_MCP_EXPECTED_VERSION is required}" ]

package_root="$(npm root --global)/@joomengine/joomla-mcp"
test -f "$package_root/dist/index.js"

install_wrapper() {
    local source_command="$1"
    local wrapper_name="$2"

    cat > "/usr/local/bin/$wrapper_name" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
export JOOMLA_MCP_CONFIG="\${JOOMLA_MCP_CONFIG:-/etc/joomla-mcp/sites.json}"
exec "$source_command" "\$@"
EOF
    chmod 0755 "/usr/local/bin/$wrapper_name"
}

install_wrapper "$(command -v joomla-mcp)" vdm-joomla-mcp
install_wrapper "$(command -v joomla-mcp-http)" vdm-joomla-mcp-http
install_wrapper "$(command -v joomla-mcp-live-test)" vdm-joomla-mcp-live-test

cat > /usr/local/bin/vdm-joomla-mcp-config-check <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

config="\${1:-/etc/joomla-mcp/sites.json}"
[ -f "\$config" ] || {
    printf 'Joomla MCP configuration does not exist: %s\n' "\$config" >&2
    exit 1
}
jq -e . "\$config" >/dev/null

mapfile -t credential_keys < <(
    jq -r '
        [
          .approval?.secretEnv,
          .sites[].api?.tokenEnv,
          .sites[].api?.updateTokenEnv
        ]
        | map(select(type == "string"))
        | unique[]
    ' "\$config"
)
for key in "\${credential_keys[@]}"; do
    [[ "\$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || {
        printf 'Unsafe credential environment name in Joomla MCP configuration: %s\n' "\$key" >&2
        exit 1
    }
    case "\$key" in
        JOOMLA_MCP_SITE_TOKEN|JOOMLA_MCP_APPROVAL_SECRET|JOOMLA_MCP_UPDATE_TOKEN) ;;
        *)
            printf 'Unsupported Joomla MCP credential reference: %s\n' "\$key" >&2
            exit 1
            ;;
    esac
    declare -gx "\$key=vdm-configuration-validation-placeholder-0123456789abcdef"
done

node --input-type=module - "\$config" <<'NODE'
import { pathToFileURL } from 'node:url';

const packageEntry = '$package_root/dist/index.js';
const { loadConfiguration } = await import(pathToFileURL(packageEntry).href);
const configPath = process.argv.at(-1);
await loadConfiguration(configPath);
process.stdout.write('Joomla MCP configuration is valid.\n');
NODE
EOF
chmod 0755 /usr/local/bin/vdm-joomla-mcp-config-check

install -d -o root -g "$AGENT_USER" -m 0750 /etc/joomla-mcp
test -f /etc/joomla-mcp/sites.readonly.example.json
rm -f /etc/joomla-mcp/sites.json

config="$AGENT_HOME/.config/opencode/opencode.json"
tmp="$(mktemp)"
jq '
  .mcp.joomla = {
    "type": "local",
    "command": ["/usr/local/bin/vdm-joomla-mcp"],
    "environment": {
      "JOOMLA_MCP_CONFIG": "/etc/joomla-mcp/sites.json"
    },
    "enabled": false,
    "timeout": 30000
  }
' "$config" > "$tmp"
install -o "$AGENT_USER" -g "$AGENT_USER" -m 0640 "$tmp" "$config"
rm -f "$tmp"

test -x /usr/local/bin/vdm-joomla-mcp
test -x /usr/local/bin/vdm-joomla-mcp-http
test -x /usr/local/bin/vdm-joomla-mcp-live-test
test -x /usr/local/bin/vdm-joomla-mcp-config-check
jq -e '.mcp.joomla.enabled == false' "$config" >/dev/null
