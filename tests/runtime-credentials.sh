#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/runtime-credentials.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid="$tmp_dir/valid.env"
cat > "$valid" <<'EOF'
GITHUB_MCP_TOKEN=github-value
JOOMLA_MCP_SITE_TOKEN=joomla-value
JOOMLA_MCP_APPROVAL_SECRET=approval-value-0123456789abcdef0123
JOOMLA_MCP_UPDATE_TOKEN=update-value
EOF
chmod 0600 "$valid"
validate_runtime_file "$valid"
runtime_value_present "$valid" JOOMLA_MCP_SITE_TOKEN
runtime_value_length_at_least "$valid" JOOMLA_MCP_APPROVAL_SECRET 32
if runtime_value_length_at_least "$valid" JOOMLA_MCP_SITE_TOKEN 128; then
    printf 'A short runtime value passed an oversized minimum length.\n' >&2
    exit 1
fi
if runtime_value_present "$valid" NEXTCLOUD_MCP_TOKEN; then
    printf 'Unexpected runtime value reported as present.\n' >&2
    exit 1
fi

duplicate="$tmp_dir/duplicate.env"
printf 'JOOMLA_MCP_SITE_TOKEN=one\nJOOMLA_MCP_SITE_TOKEN=two\n' > "$duplicate"
chmod 0600 "$duplicate"
if (validate_runtime_file "$duplicate" >/dev/null 2>&1); then
    printf 'Duplicate runtime keys were accepted.\n' >&2
    exit 1
fi

unknown="$tmp_dir/unknown.env"
printf 'UNAPPROVED_SECRET=value\n' > "$unknown"
chmod 0600 "$unknown"
if (validate_runtime_file "$unknown" >/dev/null 2>&1); then
    printf 'An unknown runtime key was accepted.\n' >&2
    exit 1
fi

link="$tmp_dir/link.env"
ln -s "$valid" "$link"
if (validate_runtime_file "$link" >/dev/null 2>&1); then
    printf 'A symlink runtime file was accepted.\n' >&2
    exit 1
fi

printf 'Runtime credential validation tests passed.\n'
