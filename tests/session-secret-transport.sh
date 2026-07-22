#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export PATH="$ROOT_DIR/tests/fixtures/session:$PATH"
export MOCK_INCUS_LOG="$tmp_dir/incus.log"
export MOCK_INCUS_LIST="$tmp_dir/list.json"
printf '[]\n' > "$MOCK_INCUS_LIST"
runtime_file="$tmp_dir/runtime.env"
sentinel="never-appear-in-incus-argv-7f3d9a"
printf 'GITHUB_MCP_TOKEN=%s\n' "$sentinel" > "$runtime_file"
chmod 0600 "$runtime_file"

"$ROOT_DIR/scripts/start-session.sh" test-vm "$runtime_file" 60s
if grep -F "$sentinel" "$MOCK_INCUS_LOG"; then
    printf 'Secret value leaked into an Incus process argument.\n' >&2
    exit 1
fi
grep -F 'LoadCredential=session.env:' "$MOCK_INCUS_LOG" >/dev/null
printf 'Session secret transport test passed.\n'
