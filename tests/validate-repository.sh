#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0

while IFS= read -r -d '' script; do
    bash -n "$script" || fail=1
done < <(find "$ROOT_DIR" -type f -name '*.sh' -print0)

if command -v shellcheck >/dev/null 2>&1; then
    mapfile -d '' scripts < <(find "$ROOT_DIR" -type f -name '*.sh' -print0)
    shellcheck -x "${scripts[@]}" || fail=1
fi

while IFS= read -r -d '' json; do
    jq empty "$json" || fail=1
done < <(find "$ROOT_DIR" -type f -name '*.json' -print0)

if command -v yamllint >/dev/null 2>&1; then
    yamllint -d '{extends: default, rules: {line-length: disable, truthy: disable, document-start: disable}}' \
        "$ROOT_DIR/incus" "$ROOT_DIR/manifest" "$ROOT_DIR/broker" "$ROOT_DIR/.gitea" || fail=1
fi

if grep -RIE \
    --exclude-dir=.git \
    --exclude='*.md' \
    --exclude='.env.example' \
    --exclude='validate-repository.sh' \
    '(BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|BW_SESSION=.+|GITEA_PACKAGE_TOKEN=.+)' \
    "$ROOT_DIR"; then
    printf 'Potential committed credential detected.\n' >&2
    fail=1
fi

if find "$ROOT_DIR" -type f \( -name 'auth.json' -o -name 'mcp-auth.json' -o -name '.git-credentials' \) | grep -q .; then
    printf 'Forbidden credential-state filename detected.\n' >&2
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
printf 'Repository validation passed.\n'
