#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/build-resources.sh"

export VDM_TEST_MEM_TOTAL_MIB=14336
export VDM_TEST_MEM_AVAILABLE_MIB=12288
export VDM_TEST_CPU_COUNT=8
export VDM_TEST_DISK_AVAILABLE_GIB=785

select_build_resources typescript default true
[ "$BUILD_SELECTED_CPUS" = 4 ]
[ "$BUILD_SELECTED_MEMORY" = 8192MiB ]
[ "$BUILD_SELECTED_DISK" = 80GiB ]
[ "$BUILD_REQUIRED_FREE_GIB" = 120 ]
[ "$BUILD_HOST_RESERVE_MIB" = 2868 ]

export VDM_TEST_MEM_AVAILABLE_MIB=3482
if (
    select_build_resources typescript default true
) >"$ROOT_DIR/build-resource-test.out" 2>&1; then
    printf 'The TypeScript resource plan accepted unsafe available memory.\n' >&2
    exit 1
fi
grep -F 'Insufficient currently available memory for typescript' \
    "$ROOT_DIR/build-resource-test.out" >/dev/null
grep -F 'Swap is not required and is not counted.' \
    "$ROOT_DIR/build-resource-test.out" >/dev/null
rm -f "$ROOT_DIR/build-resource-test.out"

export VDM_TEST_MEM_AVAILABLE_MIB=12288
export VDM_TEST_DISK_AVAILABLE_GIB=119
if (
    select_build_resources typescript default true
) >"$ROOT_DIR/build-resource-test.out" 2>&1; then
    printf 'The TypeScript resource plan accepted unsafe free storage.\n' >&2
    exit 1
fi
grep -F 'Insufficient Incus storage for typescript' \
    "$ROOT_DIR/build-resource-test.out" >/dev/null
rm -f "$ROOT_DIR/build-resource-test.out"

printf 'Build resource tests passed.\n'
