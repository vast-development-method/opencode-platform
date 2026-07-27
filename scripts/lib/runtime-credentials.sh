#!/usr/bin/env bash

allowed_runtime_key() {
    case "$1" in
        VDM_LLM_GATEWAY_URL|VDM_LLM_GATEWAY_TOKEN|\
        GITHUB_MCP_URL|GITHUB_MCP_TOKEN|\
        GITEA_MCP_URL|GITEA_MCP_TOKEN|\
        NEXTCLOUD_MCP_URL|NEXTCLOUD_MCP_TOKEN|\
        JOOMLA_MCP_URL|JOOMLA_MCP_TOKEN|\
        JOOMLA_MCP_SITE_TOKEN|JOOMLA_MCP_UPDATE_TOKEN|\
        JOOMLA_MCP_APPROVAL_SECRET|\
        JCB_MCP_URL|JCB_MCP_TOKEN|\
        STT_MCP_URL|STT_MCP_TOKEN|\
        VDM_LOCAL_LLM_BASE_URL|VDM_LOCAL_LLM_MODEL) return 0 ;;
        *) return 1 ;;
    esac
}

validate_runtime_file() {
    local file="$1"
    local line
    local key
    declare -A seen=()

    if [ ! -f "$file" ] || [ -L "$file" ]; then
        die "Runtime env must be a regular non-symlink file: $file"
    fi
    [ "$(stat -c '%u' "$file")" = "$UID" ] ||
        die "Runtime env file must be owned by UID $UID: $file"
    [ "$(stat -c '%a' "$file")" = 600 ] ||
        die "Runtime env file must have mode 0600: $file"
    [ "$(stat -c '%h' "$file")" = 1 ] ||
        die "Runtime env file must have exactly one hard link: $file"

    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" != *$'\r'* ]] || die "Runtime environment contains a carriage return: $file"
        case "$line" in
            ""|\#*) continue ;;
            *=*)
                key="${line%%=*}"
                [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] ||
                    die "Invalid runtime variable name: $key"
                allowed_runtime_key "$key" ||
                    die "Runtime variable is not allowed: $key"
                [[ -z "${seen[$key]+x}" ]] ||
                    die "Runtime variable is duplicated: $key"
                seen["$key"]=1
                ;;
            *) die "Invalid runtime environment line in $file" ;;
        esac
    done < "$file"
}

runtime_value_present() {
    local file="$1"
    local wanted="$2"
    local line

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "$wanted="*)
                [ -n "${line#*=}" ]
                return
                ;;
        esac
    done < "$file"
    return 1
}

runtime_value_length_at_least() {
    local file="$1"
    local wanted="$2"
    local minimum="$3"
    local line
    local value

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "$wanted="*)
                value="${line#*=}"
                (("${#value}" >= minimum))
                return
                ;;
        esac
    done < "$file"
    return 1
}
