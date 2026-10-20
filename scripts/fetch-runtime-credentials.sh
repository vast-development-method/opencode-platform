#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/runtime-credentials.sh"

NAME="${1:-}"
CONFIG="${2:-}"
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$ && $# == 2 ]] ||
    die "Usage: $0 INSTANCE OPENBAO_CONFIG_JSON"
for dependency in jq curl flock; do require_command "$dependency"; done

# This is controller configuration, never copied into an agent VM.
[[ -f "$CONFIG" && ! -L "$CONFIG" ]] || die 'OpenBao configuration must be a regular file'
[[ $(stat -c %u "$CONFIG") == "$UID" && $(stat -c %a "$CONFIG") == 600 && $(stat -c %h "$CONFIG") == 1 ]] ||
    die 'OpenBao configuration must be caller-owned, single-link and mode 0600'
jq -e '
  type == "object" and .schema == 1 and
  ((keys - ["schema", "address", "token_file", "ca_file", "secrets"]) | length == 0) and
  (.address | type == "string" and test("^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?$")) and
  (.token_file | type == "string" and startswith("/") and (test("[\\r\\n]") | not)) and
  ((has("ca_file") | not) or (.ca_file | type == "string" and startswith("/") and (test("[\\r\\n]") | not))) and
  (.secrets | type == "array" and length > 0 and length <= 64) and
  ([.secrets[].key] | length == (unique | length)) and
  all(.secrets[];
    type == "object" and ((keys - ["key", "mount", "path", "field"]) | length == 0) and
    (.key | type == "string" and test("^[A-Z][A-Z0-9_]*$")) and
    (.mount | type == "string" and test("^[A-Za-z0-9_-]+$")) and
    (.path | type == "string" and test("^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$")) and
    (.field | type == "string" and test("^[A-Za-z0-9_-]+$")))
' "$CONFIG" >/dev/null || die 'Invalid OpenBao KV-v2 configuration'
while IFS= read -r key; do
    allowed_runtime_key "$key" || die "Unsupported runtime credential reference: $key"
done < <(jq -r '.secrets[].key' "$CONFIG")

token_file="$(jq -r .token_file "$CONFIG")"
[[ -f "$token_file" && ! -L "$token_file" ]] || die 'OpenBao token file must be regular'
[[ $(stat -c %u "$token_file") == "$UID" && $(stat -c %a "$token_file") == 600 && $(stat -c %h "$token_file") == 1 ]] ||
    die 'OpenBao token file must be caller-owned, single-link and mode 0600'
[[ $(stat -f -c %T "$token_file") == tmpfs ]] || die 'OpenBao controller token must be on tmpfs'
token="$(cat "$token_file")"
[[ "$token" =~ ^[A-Za-z0-9._-]{1,4096}$ ]] || die 'Invalid OpenBao token encoding'

runtime_file="$("$SCRIPT_DIR/create-runtime-env.sh" "$NAME")"
exec {lock_fd}>"$runtime_file.lock"
flock -x "$lock_fd"
validate_runtime_file "$runtime_file"
temp_dir="$(mktemp -d "$(dirname "$runtime_file")/.bao-XXXXXXXX")"
trap 'rm -rf -- "$temp_dir"' EXIT
printf 'X-Vault-Token: %s\n' "$token" > "$temp_dir/headers"
unset token
cp -- "$runtime_file" "$temp_dir/runtime.env"
address="$(jq -r .address "$CONFIG")"
curl_options=(--fail --silent --show-error --proto '=https' --connect-timeout 10 --max-time 30 --max-filesize 1048576 --header "@$temp_dir/headers")
if jq -e 'has("ca_file")' "$CONFIG" >/dev/null; then
    ca_file="$(jq -r .ca_file "$CONFIG")"
    [[ -f "$ca_file" && ! -L "$ca_file" ]] || die 'CA file must be a regular certificate file'
    curl_options+=(--cacert "$ca_file")
fi
while IFS=$'\t' read -r key mount path field; do
    # No redirects: an upstream token may only reach the configured authority.
    curl "${curl_options[@]}" --output "$temp_dir/response.json" \
        "$address/v1/$mount/data/$path" || die "OpenBao retrieval failed for $key"
    jq -e --arg field "$field" '
        .data.data[$field] | type == "string" and length > 0 and
        (explode | all(. >= 32 and . != 127))
    ' "$temp_dir/response.json" >/dev/null || die "OpenBao has no valid single-line value for $key"
    # jq reads the value from a file; it never enters argv, logs or shell evaluation.
    KEY="$key" awk 'index($0, ENVIRON["KEY"] "=") != 1' "$temp_dir/runtime.env" > "$temp_dir/next.env"
    printf '%s=' "$key" >> "$temp_dir/next.env"
    jq -r --arg field "$field" '.data.data[$field]' "$temp_dir/response.json" >> "$temp_dir/next.env"
    mv -- "$temp_dir/next.env" "$temp_dir/runtime.env"
done < <(jq -r '.secrets[] | [.key, .mount, .path, .field] | @tsv' "$CONFIG")
validate_runtime_file "$temp_dir/runtime.env"
mv -f -- "$temp_dir/runtime.env" "$runtime_file"
printf '%s\n' "$runtime_file"
