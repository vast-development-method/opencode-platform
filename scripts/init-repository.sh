#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="${1:-ssh://git@git.vdm.dev/platform/vdm-opencode-platform.git}"

cd "$ROOT_DIR"
[ ! -d .git ] || {
    printf 'Repository is already initialised.\n'
    exit 0
}

git init --initial-branch=main
git add .
git commit -m "Initialize VDM OpenCode platform"
git remote add origin "$REMOTE"

printf 'Repository initialised. Review the commit, create the remote repository, then run:\n'
printf '  git push -u origin main\n'
