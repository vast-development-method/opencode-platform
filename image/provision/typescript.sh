#!/usr/bin/env bash
set -Eeuo pipefail

corepack enable
npm install --global \
    "${TYPESCRIPT_PACKAGE:?TYPESCRIPT_PACKAGE is required}" \
    "${TSX_PACKAGE:?TSX_PACKAGE is required}"

[ "$(tsc --version | awk '{print $2}')" = "$TYPESCRIPT_EXPECTED_VERSION" ]
[ "$(tsx --version | awk 'NR == 1 {print $2}')" = "$TSX_EXPECTED_VERSION" ]
