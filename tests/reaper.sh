#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export PATH="$ROOT_DIR/tests/fixtures/session:$PATH"
export MOCK_INCUS_LOG="$tmp_dir/incus.log"
export MOCK_INCUS_LIST="$tmp_dir/list.json"
cat > "$MOCK_INCUS_LIST" <<'JSON'
[
  {"name":"expired","status":"Running","config":{"user.vdm.session.expires_epoch":"100"}},
  {"name":"unexpired","status":"Running","config":{"user.vdm.session.expires_epoch":"300"}},
  {"name":"malformed","status":"Running","config":{"user.vdm.session.expires_epoch":"tomorrow"}},
  {"name":"no-expiry","status":"Running","config":{}},
  {"name":"already-stopped","status":"Stopped","config":{"user.vdm.session.expires_epoch":"50"}}
]
JSON

VDM_REAPER_NOW=200 "$ROOT_DIR/scripts/reap-expired-vms.sh"
grep -E '^stop expired ' "$MOCK_INCUS_LOG" >/dev/null
! grep -E '^stop (unexpired|malformed|no-expiry|already-stopped) ' "$MOCK_INCUS_LOG"

# Simulate Incus state after the first stop and prove a second pass is a no-op.
printf '[{"name":"expired","status":"Stopped","config":{}}]\n' > "$MOCK_INCUS_LIST"
: > "$MOCK_INCUS_LOG"
VDM_REAPER_NOW=200 "$ROOT_DIR/scripts/reap-expired-vms.sh"
! grep -E '^stop ' "$MOCK_INCUS_LOG"
printf 'VM expiry reaper tests passed.\n'
