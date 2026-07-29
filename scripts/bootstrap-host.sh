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

for utility in /usr/bin/cp /usr/bin/mv /usr/bin/rm; do
    [ -x "$utility" ] || die "Host package state is unsafe: $utility is missing or not executable. Repair dpkg before running bootstrap."
done

dpkg_audit="$(dpkg --audit)"
[ -z "$dpkg_audit" ] || {
    printf '%s\n' "$dpkg_audit" >&2
    die "dpkg reports interrupted or inconsistent packages. Repair the host before running bootstrap."
}
sudo apt-get check >/dev/null ||
    die "APT dependency checks failed. Repair the host before running bootstrap."

log "Installing host prerequisites"
sudo apt-get update

incus_candidate="$(apt-cache policy incus | awk '/Candidate:/ {print $2; exit}')"
[ -n "$incus_candidate" ] && [ "$incus_candidate" != "(none)" ] ||
    die "No Incus package candidate is available from the host's configured repositories."

incus_installed="$(
    dpkg-query -W -f='${Version}' incus 2>/dev/null || true
)"
if [ -n "$incus_installed" ] &&
    dpkg --compare-versions "$incus_installed" lt "$incus_candidate" &&
    systemctl is-active --quiet incus.service; then

    running_instances="$(
        incus_cmd list \
            --all-projects \
            status=Running \
            --format csv
    )" || die "Unable to inspect running Incus instances before a daemon upgrade."
    if [ -n "$running_instances" ] &&
        [ "${VDM_ALLOW_INCUS_UPGRADE_WITH_RUNNING_INSTANCES:-false}" != true ]; then
        printf 'Running Incus instances:\n' >&2
        printf '%s\n' "$running_instances" >&2
        die "Incus $incus_candidate is available, but upgrading could restart the daemon. Stop the listed instances or set VDM_ALLOW_INCUS_UPGRADE_WITH_RUNNING_INSTANCES=true after scheduling downtime."
    fi
fi

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    incus \
    iproute2 \
    jq \
    python3-yaml \
    qemu-system \
    shellcheck \
    yamllint \
    zstd

incus_installed="$(dpkg-query -W -f='${Version}' incus)"
[ "$incus_installed" = "$incus_candidate" ] ||
    die "Incus installation did not reach the configured repository candidate: installed $incus_installed, candidate $incus_candidate."

sudo systemctl enable --now incus.service
sudo systemctl is-active --quiet incus.service ||
    die "Incus did not become active after package installation."

server_version="$(
    incus_cmd version |
        awk -F': ' '/^Server version:/ {print $2; exit}'
)"
[ -n "$server_version" ] || die "Unable to determine the Incus server version."
version_at_least "$server_version" "$MIN_INCUS_VERSION" ||
    die "Incus $server_version is older than the supported minimum $MIN_INCUS_VERSION."
log "Using Incus server $server_version (latest configured package candidate $incus_candidate)"

if ! incus_cmd storage list --format csv 2>/dev/null | grep -q .; then
    log "Initialising Incus"
    incus_cmd admin init --minimal
fi

if ! incus_cmd remote list --format csv | cut -d, -f1 | grep -qx images; then
    incus_cmd remote add images https://images.linuxcontainers.org --protocol=simplestreams
fi

"$SCRIPT_DIR/apply-incus.sh"
"$SCRIPT_DIR/install-host-units.sh"
log "Host bootstrap complete"
