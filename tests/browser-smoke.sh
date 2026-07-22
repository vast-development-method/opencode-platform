#!/usr/bin/env bash
set -Eeuo pipefail

command -v node >/dev/null
command -v playwright >/dev/null
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/ms-playwright}"
playwright --version

output="$(mktemp --suffix=.png)"
trap 'rm -f "$output"' EXIT

playwright screenshot \
    --browser=chromium \
    'data:text/html,<main><h1>VDM%20browser%20smoke%20test</h1></main>' \
    "$output"

test -s "$output"
