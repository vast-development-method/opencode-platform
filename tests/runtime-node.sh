#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
export TEST_NODE_STATE="$tmp_dir"
# shellcheck disable=SC1091
source "$ROOT_DIR/manifest/toolchain.env"
# shellcheck disable=SC1091
source "$ROOT_DIR/image/provision/lib/node-runtime.sh"
export NODE_MAJOR NODE_EXPECTED_VERSION NODE_PACKAGE_VERSION
# The stub setup program expands its state path only when it executes.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'touch "$TEST_NODE_STATE/setup-ran"' > "$tmp_dir/setup.sh"
NODESOURCE_SETUP_SHA256="$(sha256sum "$tmp_dir/setup.sh" | awk '{print $1}')"
export NODESOURCE_SETUP_SHA256

node() {
    [ "$*" = "-p process.versions.node" ] || return 2
    [ -s "$TEST_NODE_STATE/node" ] || return 127
    cat "$TEST_NODE_STATE/node"
}
curl() {
    local destination=""
    while (($#)); do
        if [ "$1" = --output ]; then destination="$2"; shift; fi
        shift
    done
    cp "$TEST_NODE_STATE/setup.sh" "$destination"
}
apt-get() {
    printf '%s\n' "$*" >> "$TEST_NODE_STATE/apt.log"
    [[ " $* " == *" nodejs=$NODE_PACKAGE_VERSION "* ]] || return 2
    if [ "${TEST_KEEP_NODE:-false}" != true ]; then
        printf '%s\n' "$NODE_EXPECTED_VERSION" > "$TEST_NODE_STATE/node"
    fi
}
export -f node curl apt-get node_runtime_matches ensure_node_runtime

# An already compatible runtime requires no repository or package mutation.
printf '%s\n' "$NODE_EXPECTED_VERSION" > "$tmp_dir/node"
bash -c ensure_node_runtime
test ! -e "$tmp_dir/apt.log"
test ! -e "$tmp_dir/setup-ran"

# Missing, wrong-major, too-old minor, and differing patch all require the pin.
for installed in missing 22.20.0 24.15.0 24.16.0 26.1.0; do
    rm -f "$tmp_dir/node" "$tmp_dir/setup-ran" "$tmp_dir/apt.log"
    if [ "$installed" != missing ]; then printf '%s\n' "$installed" > "$tmp_dir/node"; fi
    bash -c ensure_node_runtime >/dev/null
    test -e "$tmp_dir/setup-ran"
    grep -F "nodejs=$NODE_PACKAGE_VERSION" "$tmp_dir/apt.log" >/dev/null
    [ "$(cat "$tmp_dir/node")" = "$NODE_EXPECTED_VERSION" ]
done

# A shadowed executable must fail even if APT reports a successful installation.
printf '22.20.0\n' > "$tmp_dir/node"
if TEST_KEEP_NODE=true bash -c ensure_node_runtime > "$tmp_dir/output" 2>&1; then
    printf 'A stale executable after package installation was accepted.\n' >&2
    exit 1
fi
grep -F 'Node runtime mismatch after installation' "$tmp_dir/output" >/dev/null

# Changed remote setup bytes may never execute or reach APT.
rm -f "$tmp_dir/setup-ran" "$tmp_dir/apt.log"
if NODESOURCE_SETUP_SHA256="$(printf '0%.0s' {1..64})" \
    bash -c ensure_node_runtime > "$tmp_dir/output" 2>&1; then
    printf 'An unverified NodeSource setup script was accepted.\n' >&2
    exit 1
fi
test ! -e "$tmp_dir/setup-ran"
test ! -e "$tmp_dir/apt.log"

if NODE_MAJOR=22 bash -c ensure_node_runtime > "$tmp_dir/output" 2>&1; then
    printf 'An inconsistent Node pin was accepted.\n' >&2
    exit 1
fi
printf 'Node runtime provisioning tests passed.\n'
