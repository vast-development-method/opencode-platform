#!/usr/bin/env bash
set -Eeuo pipefail

test -x /home/opencode/.local/bin/opencode
test -d /workspace
test -f /etc/opencode/opencode.json
test -f /etc/vdm-opencode-platform/build.json
jq empty /etc/opencode/opencode.json
jq empty /home/opencode/.config/opencode/opencode.json
