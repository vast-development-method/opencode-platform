#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/variant-selection.sh"

assert_selection() {
    local input="$1"
    local expected="$2"
    local -a actual=()

    parse_variant_selection "$input" actual
    [[ "${actual[*]}" == "$expected" ]] || {
        printf 'Selection %q resolved to %q; expected %q.\n' "$input" "${actual[*]}" "$expected" >&2
        exit 1
    }
}

assert_rejected() {
    local input="$1"
    local -a actual=()

    if parse_variant_selection "$input" actual 2>/dev/null; then
        printf 'Selection %q should have been rejected.\n' "$input" >&2
        exit 1
    fi
}

assert_selection "all" "base php python cpp typescript full"
assert_selection "php,typescript,full" "php typescript full"
assert_selection $'php  typescript\nfull' "php typescript full"
assert_selection "php,php,full" "php full"
assert_rejected ""
assert_rejected "unknown"
assert_rejected "all,php"
assert_rejected "php,,unknown"

printf 'Variant selection tests passed.\n'
