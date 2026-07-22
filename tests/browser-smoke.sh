#!/usr/bin/env bash
set -Eeuo pipefail

command -v node >/dev/null
npx playwright --version

output="$(mktemp --suffix=.png)"
trap 'rm -f "$output"' EXIT

npx playwright screenshot \
    --browser=chromium \
    'data:text/html,<main><h1>VDM%20browser%20smoke%20test</h1></main>' \
    "$output"

test -s "$output"
