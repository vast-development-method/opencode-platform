#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

list_tsv() {
    project_cmd list --format json | jq -r '
      ["NAME","STATE","OWNER","TEAM","IMAGE","POLICY","SIZE","TRUST","EXPIRES"],
      (.[] | [
        .name,
        .status,
        (.config["user.vdm.owner"] // "-"),
        (.config["user.vdm.team"] // "-"),
        (.config["user.vdm.variant"] // "-"),
        (.config["user.vdm.policy"] // "-"),
        (.config["user.vdm.size"] // "-"),
        (.config["user.vdm.repository.trust"] // "-"),
        (.config["user.vdm.session.expires_epoch"] // "-")
      ]) | @tsv'
}

if command -v column >/dev/null 2>&1; then
    list_tsv | column -t -s $'\t'
else
    list_tsv
fi
