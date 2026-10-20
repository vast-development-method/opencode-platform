#!/usr/bin/env bash

joomla_mcp_enabled() {
    local instance="$1"
    project_cmd exec "$instance" --mode=non-interactive -- \
        jq -e '[.mcp | to_entries[] | select((.key == "joomla" or (.key | startswith("joomla_"))) and .value.enabled == true)] | length > 0' \
        "$AGENT_HOME/.config/opencode/opencode.json" >/dev/null 2>&1
}

validate_joomla_mcp_runtime_credentials() {
    local instance="$1" runtime_file="$2" config=/etc/joomla-mcp/sites.json key references
    joomla_mcp_enabled "$instance" || return 0
    project_cmd exec "$instance" --mode=non-interactive -- \
        /usr/local/bin/vdm-joomla-mcp-config-check "$config" >/dev/null ||
        die "Native Joomla MCP configuration is invalid or missing in $instance"
    # The jq variables are evaluated inside the guest, not by this shell.
    # shellcheck disable=SC2016
    references="$(project_cmd exec "$instance" --mode=non-interactive -- \
        jq -er --slurpfile sites "$config" '
          if .mcp.joomla.enabled == true then error("Configure a named native Joomla connection") else . end
          | .mcp | to_entries[]
          | select((.key | startswith("joomla_")) and .value.enabled == true)
          | .key[7:] as $alias | $sites[0].sites[$alias].tokenEnv
          | if type == "string" then . else error("Unknown configured Joomla alias") end
        ' "$AGENT_HOME/.config/opencode/opencode.json")" || die 'Could not resolve enabled Joomla credential references.'
    [[ -n "$references" ]] || die 'Joomla configuration has no credential references.'
    while IFS= read -r key; do
        key="${key%$'\r'}"
        allowed_runtime_key "$key" || die "Unsupported Joomla credential reference: $key"
        runtime_value_present "$runtime_file" "$key" ||
            die "Set $key in the protected runtime credential file before starting Joomla MCP"
    done <<< "$references"
}
