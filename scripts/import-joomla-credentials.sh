#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/runtime-credentials.sh"
NAME="${1:-}"
INPUT="${2:-}"
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ && $# == 2 ]] ||
    die "Usage: $0 INSTANCE DUCTOR_CLIENT_JSON"
[[ -f "$INPUT" && ! -L "$INPUT" && $(stat -c %u "$INPUT") == "$UID" &&
   $(stat -c %a "$INPUT") == 600 && $(stat -c %h "$INPUT") == 1 ]] ||
    die 'Client credentials must be caller-owned, single-link and mode 0600'
jq -e '
  .schema == 1 and (.url | type == "string") and
  (.alias | type == "string" and test("^[a-z][a-z0-9_-]{0,63}$")) and
  (.write_enabled | type == "boolean") and
  (.token | type == "string" and length > 0 and length <= 8192 and (explode | all(. >= 33 and . != 127)))
' "$INPUT" >/dev/null || die 'Invalid Ductor Joomla client credential document'
alias="$(jq -r .alias "$INPUT")"
url="$(jq -r .url "$INPUT")"
access='readonly'
if jq -e '.write_enabled' "$INPUT" >/dev/null; then access='write'; fi
"$SCRIPT_DIR/configure-joomla-mcp.sh" "$NAME" "$url" "$alias" "$access"
if [[ "$alias" == company ]]; then
    key=JOOMLA_MCP_SITE_TOKEN
else
    key="JOOMLA_MCP_${alias^^}_TOKEN"
    key="${key//-/_}"
fi
allowed_runtime_key "$key" || die 'Unsupported client alias'
runtime="$("$SCRIPT_DIR/create-runtime-env.sh" "$NAME")"
exec {lock_fd}>"$runtime.lock"
flock -x "$lock_fd"
temp="$(mktemp "$(dirname "$runtime")/.joomla-XXXXXXXX")"
trap 'rm -f -- "$temp"' EXIT
validate_runtime_file "$runtime"
KEY="$key" awk 'index($0, ENVIRON["KEY"] "=") != 1' "$runtime" > "$temp"
printf '%s=' "$key" >> "$temp"
jq -r .token "$INPUT" >> "$temp"
validate_runtime_file "$temp"
mv -f -- "$temp" "$runtime"
printf 'Scoped Joomla credentials installed in %s\n' "$runtime"
