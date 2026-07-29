#!/usr/bin/env bash
set -Eeuo pipefail

corepack enable
npm install --global \
    "${TYPESCRIPT_PACKAGE:?TYPESCRIPT_PACKAGE is required}" \
    "${TSX_PACKAGE:?TSX_PACKAGE is required}"

installed_typescript="$(
    tsc --version |
        awk 'NR == 1 {print $2}'
)"

installed_tsx="$(
    tsx --version |
        awk 'NR == 1 {print $2}'
)"
installed_tsx="${installed_tsx#v}"

if [ "$installed_typescript" != "$TYPESCRIPT_EXPECTED_VERSION" ]; then
    printf \
        'TypeScript version mismatch: expected %s, got %s\n' \
        "$TYPESCRIPT_EXPECTED_VERSION" \
        "$installed_typescript" >&2
    exit 1
fi

if [ "$installed_tsx" != "$TSX_EXPECTED_VERSION" ]; then
    printf \
        'TSX version mismatch: expected %s, got %s\n' \
        "$TSX_EXPECTED_VERSION" \
        "$installed_tsx" >&2
    exit 1
fi
