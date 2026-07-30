#!/usr/bin/env bash

joomla_mcp_enabled() {
    local instance="$1"

    project_cmd exec "$instance" --mode=non-interactive -- \
        jq -e '.mcp.joomla.enabled == true' \
        "$AGENT_HOME/.config/opencode/opencode.json" >/dev/null 2>&1
}

validate_joomla_mcp_runtime_credentials() {
    local instance="$1"
    local runtime_file="$2"
    local config=/etc/joomla-mcp/sites.json
    local key
    local -a required_keys=()

    joomla_mcp_enabled "$instance" || return 0

    project_cmd exec "$instance" --mode=non-interactive -- \
        test -x /usr/local/bin/vdm-joomla-mcp ||
        die "Joomla MCP is enabled but is not installed in $instance"
    project_cmd exec "$instance" --mode=non-interactive -- \
        test -r "$config" ||
        die "Joomla MCP is enabled but has no configuration in $instance"
    project_cmd exec "$instance" --mode=non-interactive -- \
        /usr/local/bin/vdm-joomla-mcp-config-check "$config" >/dev/null ||
        die "Joomla MCP configuration validation failed in $instance"

    mapfile -t required_keys < <(
        project_cmd exec "$instance" --mode=non-interactive -- \
            jq -r '
                [
                  .approval?.secretEnv,
                  .sites[].api?.tokenEnv,
                  .sites[].api?.updateTokenEnv
                ]
                | map(select(type == "string"))
                | unique[]
            ' "$config" | tr -d '\r'
    )
    (("${#required_keys[@]}" > 0)) ||
        die "Joomla MCP configuration has no runtime credential references"

    for key in "${required_keys[@]}"; do
        allowed_runtime_key "$key" ||
            die "Joomla MCP configuration requests an unsupported credential: $key"
        runtime_value_present "$runtime_file" "$key" ||
            die "Set $key in the protected runtime credential file before starting Joomla MCP"
        if [ "$key" = JOOMLA_MCP_APPROVAL_SECRET ]; then
            runtime_value_length_at_least "$runtime_file" "$key" 32 ||
                die "JOOMLA_MCP_APPROVAL_SECRET must contain at least 32 characters"
        fi
    done
}
