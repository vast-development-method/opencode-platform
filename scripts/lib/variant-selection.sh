#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

LOCAL_RELEASE_ALL_VARIANTS=("${PLATFORM_RELEASE_IMAGES[@]}")

parse_variant_selection() {
    local raw_selection="${1-}"
    local output_name="${2:?Output array name is required}"
    local normalized
    local variant
    local -a requested=()
    local -n output="$output_name"
    local -A seen=()

    output=()
    normalized="${raw_selection//,/ }"

    IFS=$' \t\r\n' read -r -d '' -a requested < <(printf '%s\0' "$normalized") || true
    if (("${#requested[@]}" == 0)); then
        printf 'LOCAL_BUILD_VARIANTS selected no variants.\n' >&2
        return 2
    fi

    if (("${#requested[@]}" > 1)); then
        for variant in "${requested[@]}"; do
            if [[ "$variant" == "all" ]]; then
                printf 'LOCAL_BUILD_VARIANTS cannot combine all with named variants.\n' >&2
                return 2
            fi
        done
    fi

    for variant in "${requested[@]}"; do
        if [[ "$variant" == "all" ]]; then
            output=("${LOCAL_RELEASE_ALL_VARIANTS[@]}")
            return 0
        fi

        if ! variant_exists "$variant"; then
            printf 'Unknown variant: %s\n' "$variant" >&2
            return 2
        fi

        if [[ -z "${seen[$variant]:-}" ]]; then
            output+=("$variant")
            seen["$variant"]=1
        fi
    done
}
