#!/usr/bin/env bash
set -Eeuo pipefail

for forbidden in \
    /home/opencode/.local/share/opencode/auth.json \
    /home/opencode/.local/share/opencode/mcp-auth.json \
    /home/opencode/.git-credentials \
    /home/opencode/.ssh/id_rsa \
    /home/opencode/.ssh/id_ed25519; do
    test ! -e "$forbidden"
done

! find /home/opencode -xdev -type f \( -name '*.token' -o -name '*.secret' -o -name '*.key' \) -print -quit | grep -q .
