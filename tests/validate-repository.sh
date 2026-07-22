#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0

find_args=("$ROOT_DIR" -type f -not -path "$ROOT_DIR/.git/*" -not -path "$ROOT_DIR/build/*")

while IFS= read -r -d '' script; do
    bash -n "$script" || fail=1
done < <(find "${find_args[@]}" -name '*.sh' -print0)

if command -v shellcheck >/dev/null 2>&1; then
    mapfile -d '' scripts < <(find "${find_args[@]}" -name '*.sh' -print0)
    if (("${#scripts[@]}" > 0)); then
        shellcheck -x "${scripts[@]}" || fail=1
    fi
fi

bash "$ROOT_DIR/tests/variant-selection.sh" || fail=1

if command -v make >/dev/null 2>&1; then
    make -C "$ROOT_DIR" --dry-run help local-release >/dev/null || fail=1
fi

while IFS= read -r -d '' json; do
    jq empty "$json" || fail=1
done < <(find "${find_args[@]}" -name '*.json' -print0)

if command -v yamllint >/dev/null 2>&1; then
    yaml_paths=()
    for path in incus manifest broker .github .gitea; do
        [ -e "$ROOT_DIR/$path" ] && yaml_paths+=("$ROOT_DIR/$path")
    done
    yamllint -d '{extends: default, rules: {line-length: disable, truthy: disable, document-start: disable}}' \
        "${yaml_paths[@]}" || fail=1
fi

if grep -RIE --exclude-dir=.git --exclude-dir=build --exclude=validate-repository.sh \
    '(nikosdion/joomla-mcp-php|OnepointConsultingLtd/joomla-mcp-server|joomla_mcp4joomla|joomla_component_mcp)' \
    "$ROOT_DIR"; then
    printf 'A non-VDM Joomla MCP reference is still present.\n' >&2
    fail=1
fi

if grep -RIE --exclude-dir=.git --exclude-dir=build --exclude='*.md' --exclude=validate-repository.sh \
    '(@latest|REVIEW_AND_PIN)' "$ROOT_DIR"; then
    printf 'A floating production dependency is still present.\n' >&2
    fail=1
fi

if grep -RIE '\$\{\{[[:space:]]*gitea\.' "$ROOT_DIR/.github/workflows"; then
    printf 'A GitHub workflow contains a Gitea-only expression context.\n' >&2
    fail=1
fi

if grep -RIE '\$\{\{[[:space:]]*github\.' "$ROOT_DIR/.gitea/workflows"; then
    printf 'A Gitea workflow contains a GitHub-only expression context.\n' >&2
    fail=1
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

if find "${find_args[@]}" \( -name 'auth.json' -o -name 'mcp-auth.json' -o -name '.git-credentials' \) | grep -q .; then
    printf 'Forbidden credential-state filename detected.\n' >&2
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
printf 'Repository validation passed.\n'
