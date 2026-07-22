#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

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
  ]) | @tsv' | column -t -s $'\t'
