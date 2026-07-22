#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

[ -r /etc/os-release ] || die "Cannot identify host operating system."
# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}:${ID_LIKE:-}" in
    ubuntu:*|debian:*|*:debian*) ;;
    *) die "Supported hosts are Ubuntu and Debian." ;;
esac

log "Installing host prerequisites"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    incus \
    jq \
    shellcheck \
    yamllint \
    zstd

sudo systemctl enable --now incus.service >/dev/null 2>&1 || true

if ! incus_cmd storage list --format csv 2>/dev/null | grep -q .; then
    log "Initialising Incus"
    incus_cmd admin init --minimal
fi

if ! incus_cmd remote list --format csv | cut -d, -f1 | grep -qx images; then
    incus_cmd remote add images https://images.linuxcontainers.org --protocol=simplestreams
fi

"$SCRIPT_DIR/apply-incus.sh"
log "Host bootstrap complete"
