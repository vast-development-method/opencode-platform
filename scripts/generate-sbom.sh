#!/usr/bin/env bash
set -Eeuo pipefail
PACKAGE_DIR="${1:?package directory required}"
command -v syft >/dev/null 2>&1 || { printf 'syft is required\n' >&2; exit 1; }
syft "dir:$PACKAGE_DIR/payload" --output "spdx-json=$PACKAGE_DIR/sbom.spdx.json"
jq -e '.spdxVersion and (.packages | type == "array")' "$PACKAGE_DIR/sbom.spdx.json" >/dev/null
