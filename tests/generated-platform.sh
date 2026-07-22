#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 "$ROOT_DIR/scripts/generate-platform.py" --check
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/common.sh"

for image in "${PLATFORM_IMAGES[@]}"; do
    variant_exists "$image"
    test -f "$ROOT_DIR/incus/profiles/generated/images/$image.yaml"
    for component in ${PLATFORM_IMAGE_COMPONENTS[$image]}; do
        provision="${PLATFORM_COMPONENT_PROVISION[$component]:-}"
        [ -z "$provision" ] || test -f "$ROOT_DIR/image/provision/$provision"
    done
done

for policy in "${!PLATFORM_POLICY_STATUS[@]}"; do
    test -f "$ROOT_DIR/incus/profiles/generated/policies/$policy.yaml"
    test -f "$ROOT_DIR/incus/acls/generated/$policy.yaml"
done
for size in "${!PLATFORM_SIZE_CPUS[@]}"; do
    test -f "$ROOT_DIR/incus/profiles/generated/sizes/$size.yaml"
done

github="$(python3 "$ROOT_DIR/scripts/generate-platform.py" --matrix github)"
gitea="$(python3 "$ROOT_DIR/scripts/generate-platform.py" --matrix gitea)"
[ "$github" = "$gitea" ]
printf 'Generated platform tests passed.\n'
