#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$ROOT_DIR/image/files/usr/local/libexec/vdm-joomla-mcp"
tmp_dir="$(mktemp -d)"
server_pid=''
cleanup() { [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true; rm -rf "$tmp_dir"; }
trap cleanup EXIT
JOOMLA_TEST_REAL_JQ="$(command -v jq)"
JOOMLA_TEST_REAL_CURL="$(command -v curl)"
export JOOMLA_TEST_REAL_JQ JOOMLA_TEST_REAL_CURL
export JOOMLA_TEST_ARGV_LOG="$tmp_dir/arguments.log"
mkdir "$tmp_dir/bin"
cat > "$tmp_dir/bin/jq" <<'WRAPPER'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\0' "$0" "$@" >> "$JOOMLA_TEST_ARGV_LOG"
case "${0##*/}" in
    jq) exec "$JOOMLA_TEST_REAL_JQ" "$@" ;;
    curl) exec "$JOOMLA_TEST_REAL_CURL" "$@" ;;
esac
WRAPPER
cp "$tmp_dir/bin/jq" "$tmp_dir/bin/curl"
chmod 0755 "$tmp_dir/bin/jq" "$tmp_dir/bin/curl"
export PATH="$tmp_dir/bin:$PATH"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=127.0.0.1 \
    -addext 'subjectAltName=IP:127.0.0.1' -keyout "$tmp_dir/key.pem" -out "$tmp_dir/cert.pem" >/dev/null 2>&1
python3 "$ROOT_DIR/tests/fixtures/joomla/http-server.py" "$tmp_dir" &
server_pid=$!
for _ in {1..100}; do [[ -f "$tmp_dir/port" ]] && break; sleep 0.05; done
[[ -s "$tmp_dir/port" ]]
base="https://127.0.0.1:$(cat "$tmp_dir/port")"
export CURL_CA_BUNDLE="$tmp_dir/cert.pem"
export JOOMLA_MCP_CONFIG="$tmp_dir/sites.json"
export JOOMLA_MCP_SITE_TOKEN_FILE="$tmp_dir/token"
printf 'fixture-token\n' > "$tmp_dir/token"
chmod 0600 "$tmp_dir/token"
config() {
    jq -n --arg url "$base/$1/api/index.php/v1/joomengine-mcp" \
        '{version:1,defaultSite:"company",sites:{company:{url:$url,tokenEnv:"JOOMLA_MCP_SITE_TOKEN",access:"readonly"}}}' > "$JOOMLA_MCP_CONFIG"
}
config joomla
"$helper" read-test company "$tmp_dir/evidence" >/dev/null
jq -e 'length == 5' "$tmp_dir/evidence/tools.json" >/dev/null
jq -se '[.[] | select(.method == "tools/call") | .params.name] == ["joomla_sites_list","joomla_capabilities","joomla_content_articles_list"]' \
    "$tmp_dir/requests.jsonl" >/dev/null
[[ "$(stat -c '%a' "$tmp_dir/evidence/tools.json")" == 600 ]]
# Calls carry exactly supplied arguments and preserve the server job identity.
printf '{"jobId":"fixture-1"}\n' > "$tmp_dir/arguments.json"
"$helper" call company joomla_job_status "$tmp_dir/arguments.json" --confirm-call > "$tmp_dir/job.json"
jq -e '.structuredContent.jobId == "fixture-1" and .structuredContent.status == "completed"' "$tmp_dir/job.json" >/dev/null
before="$(wc -l < "$tmp_dir/requests.jsonl")"
if "$helper" call company joomla_job_status "$tmp_dir/arguments.json" >/dev/null 2>&1; then exit 1; fi
[[ "$before" == "$(wc -l < "$tmp_dir/requests.jsonl")" ]]
# A returned uncertain write is reported and never retried.
sentinel='private-tool-password-must-not-enter-argv-7b3a'
printf '{"confirmationToken":"%s"}\n' "$sentinel" > "$tmp_dir/arguments.json"
if "$helper" call company joomla_write_apply "$tmp_dir/arguments.json" --confirm-call > "$tmp_dir/failure.json" 2>/dev/null; then exit 1; fi
jq -e '.isError == true' "$tmp_dir/failure.json" >/dev/null
jq -se '[.[] | select(.method == "tools/call" and .params.name == "joomla_write_apply")] | length == 1' \
    "$tmp_dir/requests.jsonl" >/dev/null
if grep -aF "$sentinel" "$JOOMLA_TEST_ARGV_LOG" >/dev/null || grep -aF fixture-token "$JOOMLA_TEST_ARGV_LOG" >/dev/null; then
    printf 'Tool input or Joomla token leaked into a jq/curl process argument.\n' >&2; exit 1
fi
# Repeated cursors fail instead of hiding partial discovery.
config loop
if "$helper" discover company >/dev/null 2>&1; then exit 1; fi
# Redirects are not followed, including with a valid token and CA.
config redirect
before="$(wc -l < "$tmp_dir/requests.jsonl")"
if "$helper" discover company >/dev/null 2>&1; then exit 1; fi
[[ "$(( $(wc -l < "$tmp_dir/requests.jsonl") - before ))" == 1 ]]
config joomla
if CURL_CA_BUNDLE=/dev/null "$helper" discover company >/dev/null 2>&1; then exit 1; fi
chmod 0644 "$tmp_dir/token"
if "$helper" discover company >/dev/null 2>&1; then exit 1; fi
printf 'Native Joomla HTTPS, pagination, SSE, token-file, read and call tests passed.\n'
