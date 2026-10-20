#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d /dev/shm/vdm-bao-test-XXXXXXXX)"
trap 'rm -rf -- "$work"' EXIT
chmod 0700 "$work"
mkdir "$work/bin"
cat > "$work/bin/curl" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
output=''
headers=''
printf '%s\n' "$@" >> "$BAO_TEST_LOG"
while (($#)); do
    case "$1" in
        --output) output="$2"; shift 2 ;;
        --header) headers="${2#@}"; shift 2 ;;
        *) shift ;;
    esac
done
[[ -f "$headers" && $(stat -c %a "$headers") == 600 ]]
grep -q '^X-Vault-Token: ' "$headers"
[[ "${BAO_TEST_FAIL:-false}" != true ]] || exit 22
cp "$BAO_TEST_RESPONSE" "$output"
SH
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH" VDM_RUNTIME_BASE="$work"
export BAO_TEST_RESPONSE="$work/response.json" BAO_TEST_LOG="$work/requests.log"
printf 'test-controller-identity\n' > "$work/bao-token"
chmod 0600 "$work/bao-token"
jq -n --arg token "$work/bao-token" '{schema:1,address:"https://bao.example.test:8200",token_file:$token,secrets:[{key:"JOOMLA_MCP_SITE_TOKEN",mount:"kv",path:"joomla/company",field:"token"}]}' > "$work/config.json"
chmod 0600 "$work/config.json"
printf '%s\n' '{"data":{"data":{"token":"test-joomla-identity"}}}' > "$BAO_TEST_RESPONSE"
runtime="$("$ROOT/scripts/fetch-runtime-credentials.sh" worker "$work/config.json")"
grep -q '^JOOMLA_MCP_SITE_TOKEN=test-joomla-identity$' "$runtime"
if grep -q 'test-controller-identity\|test-joomla-identity' "$BAO_TEST_LOG"; then
    printf 'A secret entered the command arguments\n' >&2; exit 1
fi
[[ $(stat -c %a "$runtime") == 600 ]]
before="$(sha256sum "$runtime")"
export BAO_TEST_FAIL=true
if "$ROOT/scripts/fetch-runtime-credentials.sh" worker "$work/config.json" >/dev/null 2>&1; then
    printf 'HTTP failure was accepted\n' >&2; exit 1
fi
[[ $(sha256sum "$runtime") == "$before" ]]
unset BAO_TEST_FAIL
printf '%s\n' '{"data":{"data":{"token":"bad\nINJECTED=value"}}}' > "$BAO_TEST_RESPONSE"
if "$ROOT/scripts/fetch-runtime-credentials.sh" worker "$work/config.json" >/dev/null 2>&1; then
    printf 'Multiline credential was accepted\n' >&2; exit 1
fi
[[ $(sha256sum "$runtime") == "$before" ]]
jq '.secrets[0].path = "../sys"' "$work/config.json" > "$work/invalid.json"
chmod 0600 "$work/invalid.json"
if "$ROOT/scripts/fetch-runtime-credentials.sh" worker "$work/invalid.json" >/dev/null 2>&1; then
    printf 'Path traversal was accepted\n' >&2; exit 1
fi
chmod 0644 "$work/bao-token"
if "$ROOT/scripts/fetch-runtime-credentials.sh" worker "$work/config.json" >/dev/null 2>&1; then
    printf 'Publicly readable controller token was accepted\n' >&2; exit 1
fi
[[ -z $(find "$work/vdm-opencode" -name '.bao-*' -print -quit) ]]
printf 'OpenBao credential retrieval and failure isolation passed.\n'
