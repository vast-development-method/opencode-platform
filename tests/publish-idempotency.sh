#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export PATH="$ROOT_DIR/tests/fixtures/gitea:$ROOT_DIR/tests/fixtures:$PATH"
export MOCK_INCUS_LOG="$tmp_dir/incus.log"
export MOCK_GITEA_ROOT="$tmp_dir/gitea"
export MOCK_COSIGN_LOG="$tmp_dir/cosign.log"
install -d -m 0700 "$MOCK_GITEA_ROOT"
printf -v GITEA_PACKAGE_TOKEN '%s' test-token
export GITEA_PACKAGE_TOKEN

package_dir="$tmp_dir/package"
"$ROOT_DIR/scripts/package-image.sh" base "$package_dir" >/dev/null
platform_version="$(<"$ROOT_DIR/VERSION")"
artifact_id="vdm-opencode-base-${platform_version}-amd64"

publish() {
    GITEA_BASE_URL=https://gitea.invalid \
    GITEA_PACKAGE_OWNER=platform \
    GITEA_PACKAGE_USER=publisher \
    COSIGN_KEY=test-signing-key \
        "$ROOT_DIR/scripts/publish-gitea-package.sh" base "$package_dir"
}

publish > "$tmp_dir/first.out"
marker="$MOCK_GITEA_ROOT/${artifact_id}.complete.tar"
[ -f "$marker" ]
first_sha="$(sha256sum "$marker" | awk '{print $1}')"
sleep 1
publish > "$tmp_dir/second.out"
second_sha="$(sha256sum "$marker" | awk '{print $1}')"
[ "$first_sha" = "$second_sha" ] || {
    printf 'Completion marker changed during an idempotent retry.\n' >&2
    exit 1
}
grep -F 'Existing atomic package marker is valid' "$tmp_dir/second.out" >/dev/null
[ "$(wc -l < "$MOCK_COSIGN_LOG")" -eq 1 ] || {
    printf 'A valid existing marker was signed again during retry.\n' >&2
    exit 1
}

install -d "$tmp_dir/marker"
tar -xf "$marker" -C "$tmp_dir/marker"
packaged_at="$(jq -r '.packaged_at' "$package_dir/manifest.json")"
jq -e --arg packaged_at "$packaged_at" \
    '.published_at == $packaged_at' \
    "$tmp_dir/marker/release-entry.json" >/dev/null
[ -f "$tmp_dir/marker/release-entry.sigstore.json" ]

printf 'Gitea publication idempotency tests passed.\n'
