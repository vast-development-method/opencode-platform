#!/usr/bin/env bash

# This file is sourced by the common guest provisioner and its focused tests.
node_runtime_matches() {
    local actual
    actual="$(node -p 'process.versions.node' 2>/dev/null)" || return 1
    [ "$actual" = "${NODE_EXPECTED_VERSION:?NODE_EXPECTED_VERSION is required}" ]
}

ensure_node_runtime() (
    set -Eeuo pipefail
    : "${NODE_MAJOR:?NODE_MAJOR is required}"
    : "${NODE_EXPECTED_VERSION:?NODE_EXPECTED_VERSION is required}"
    : "${NODE_PACKAGE_VERSION:?NODE_PACKAGE_VERSION is required}"
    : "${NODESOURCE_SETUP_SHA256:?NODESOURCE_SETUP_SHA256 is required}"
    [[ "$NODE_MAJOR" =~ ^[0-9]+$ &&
       "$NODE_EXPECTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ &&
       "$NODE_EXPECTED_VERSION" == "$NODE_MAJOR."* &&
       "$NODE_PACKAGE_VERSION" == "$NODE_EXPECTED_VERSION-"* &&
       "$NODESOURCE_SETUP_SHA256" =~ ^[a-f0-9]{64}$ ]] || {
        printf 'Node runtime pins are invalid or inconsistent.\n' >&2
        exit 1
    }

    node_runtime_matches && exit 0
    nodesource_setup="$(mktemp)"
    trap 'rm -f "$nodesource_setup"' EXIT
    curl --fail --silent --show-error --location \
        "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" \
        --output "$nodesource_setup"
    printf '%s  %s\n' "$NODESOURCE_SETUP_SHA256" "$nodesource_setup" |
        sha256sum --check --strict
    bash "$nodesource_setup"
    # A base image may already contain a different major or a newer package.
    # Select the approved package explicitly and verify the executable on PATH.
    apt-get install -y --no-install-recommends --allow-downgrades \
        "nodejs=$NODE_PACKAGE_VERSION"
    node_runtime_matches || {
        printf 'Node runtime mismatch after installation: expected %s, got %s\n' \
            "$NODE_EXPECTED_VERSION" "$(node -p 'process.versions.node' 2>/dev/null || printf unavailable)" >&2
        exit 1
    }
)
