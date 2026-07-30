#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export PATH="$ROOT_DIR/tests/fixtures/session:$PATH"
export MOCK_INCUS_LOG="$tmp_dir/incus.log"
export MOCK_INCUS_LIST="$tmp_dir/list.json"
printf '[]\n' > "$MOCK_INCUS_LIST"

env -u USER \
    PATH="$PATH" \
    MOCK_INCUS_LOG="$MOCK_INCUS_LOG" \
    MOCK_INCUS_LIST="$MOCK_INCUS_LIST" \
    MOCK_INCUS_INSTANCE_EXISTS=false \
    "$ROOT_DIR/scripts/launch-vm.sh" base test-unset-user connected small
grep -F 'user.vdm.owner=unknown' "$MOCK_INCUS_LOG" >/dev/null
grep -F 'user.vdm.variant=base' "$MOCK_INCUS_LOG" >/dev/null

: > "$MOCK_INCUS_LOG"
if env -u USER \
    PATH="$PATH" \
    MOCK_INCUS_LOG="$MOCK_INCUS_LOG" \
    MOCK_INCUS_LIST="$MOCK_INCUS_LIST" \
    MOCK_INCUS_INSTANCE_EXISTS=false \
    MOCK_INCUS_START_FAIL=true \
    "$ROOT_DIR/scripts/launch-vm.sh" base test-failed-launch connected small \
    >"$tmp_dir/failed-launch.out" 2>&1; then
    printf 'Launch unexpectedly succeeded after the mocked start failure.\n' >&2
    exit 1
fi
grep -E '^delete test-failed-launch --force ' "$MOCK_INCUS_LOG" >/dev/null

: > "$MOCK_INCUS_LOG"
"$ROOT_DIR/scripts/stop-session.sh" test-cleanup
grep -F 'find /run -mindepth 1 -maxdepth 1 -type d' "$MOCK_INCUS_LOG" >/dev/null
grep -F -- "-name vdm-opencode-\\*" "$MOCK_INCUS_LOG" >/dev/null

minimal_bin="$tmp_dir/minimal-bin"
install -d "$minimal_bin"
for command in bash cat dirname incus jq; do
    command_path="$(command -v "$command")"
    ln -s "$command_path" "$minimal_bin/$command"
done
cat > "$MOCK_INCUS_LIST" <<'JSON'
[
  {
    "name": "portable-list",
    "status": "Running",
    "config": {
      "user.vdm.owner": "tester",
      "user.vdm.variant": "base"
    }
  }
]
JSON
PATH="$minimal_bin" \
    MOCK_INCUS_LOG="$MOCK_INCUS_LOG" \
    MOCK_INCUS_LIST="$MOCK_INCUS_LIST" \
    "$ROOT_DIR/scripts/list-vms.sh" > "$tmp_dir/list.out"
grep -F $'NAME\tSTATE\tOWNER' "$tmp_dir/list.out" >/dev/null
grep -F $'portable-list\tRunning\ttester' "$tmp_dir/list.out" >/dev/null

if MOCK_INCUS_DIRECT_ACCESS=false \
    "$ROOT_DIR/scripts/list-vms.sh" > "$tmp_dir/incus-access.out" 2>&1; then
    printf 'A normal command unexpectedly used privileged Incus fallback.\n' >&2
    exit 1
fi
grep -E \
    'Direct Incus access failed|Incus is installed but its daemon is unavailable' \
    "$tmp_dir/incus-access.out" >/dev/null

: > "$MOCK_INCUS_LOG"
AGENT_USER=agenttest \
AGENT_HOME=/srv/agenttest \
    "$ROOT_DIR/scripts/mcp-toggle.sh" test-mcp git false
grep -F -- '--env AGENT_USER=agenttest' "$MOCK_INCUS_LOG" >/dev/null
grep -F -- '--env AGENT_HOME=/srv/agenttest' "$MOCK_INCUS_LOG" >/dev/null

printf 'Runtime regression tests passed.\n'
