#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_SCRIPT="$ROOT_DIR/image/files/usr/local/libexec/vdm-opencode-session"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

credentials="$tmp_dir/credentials"
workspace="$tmp_dir/workspace"
capture="$tmp_dir/exec-arguments"
install -d -m 0700 "$credentials" "$workspace"
printf 'JOOMLA_MCP_SITE_TOKEN=test-token-that-is-never-captured\n' \
    > "$credentials/session.env"
chmod 0600 "$credentials/session.env"

export \
    CREDENTIALS_DIRECTORY="$credentials" \
    VDM_SESSION_ID=guest-exec-test \
    VDM_SESSION_MODE=joomla-read-test \
    VDM_AGENT_HOME="$tmp_dir/home" \
    VDM_WORKSPACE_ROOT="$workspace" \
    VDM_JOOMLA_SITE_ALIAS=company \
    VDM_JOOMLA_TEST_OUTPUT="$workspace/.artifacts/joomla-mcp/test" \
    CAPTURE_FILE="$capture" \
    SESSION_SCRIPT

bash -c '
    install() {
        :
    }
    exec() {
        printf "%s\n" "$@" > "$CAPTURE_FILE"
    }
    source "$SESSION_SCRIPT"
'

mapfile -t arguments < "$capture"
expected=(
    /usr/local/bin/vdm-joomla-mcp-live-test
    --config
    /etc/joomla-mcp/sites.json
    --site
    company
    --profile
    read
    --joomla-path
    api
    --mcp-transport
    stdio
    --non-interactive
    --output
    "$workspace/.artifacts/joomla-mcp/test"
)
[ "${#arguments[@]}" -eq "${#expected[@]}" ]
for index in "${!expected[@]}"; do
    [ "${arguments[$index]}" = "${expected[$index]}" ] || {
        printf 'Guest argument %s was %q; expected %q.\n' \
            "$index" "${arguments[$index]}" "${expected[$index]}" >&2
        exit 1
    }
done

if grep -R -n 'vdm-jomla' \
    "$ROOT_DIR/image" \
    "$ROOT_DIR/scripts" \
    "$ROOT_DIR/docs" \
    "$ROOT_DIR/README.md"; then
    printf 'The misspelled Joomla executable is still referenced.\n' >&2
    exit 1
fi

printf 'Guest execution tests passed.\n'
