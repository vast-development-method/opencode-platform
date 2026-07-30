# Host and network safety

This platform uses native Incus virtual machines and managed Linux bridge
networks. Host preparation is intentionally fail-closed: a repository command
must never repair the package manager by removing packages, replace a core
utility provider, rewrite an existing network, or inject firewall rules behind
the operator's back.

## Incus installation and upgrades

`scripts/bootstrap-host.sh` supports Ubuntu and Debian hosts. It runs
`apt-get update`, installs the newest `incus` candidate from repositories that
are already configured, and verifies the installed package and server version.
It does not add the Zabbly repository or any other package source.

Incus recommends an LTS branch for production. Ubuntu and Debian provide native
packages; Zabbly also provides supported current packages for listed
distributions. Selecting or changing that source is an operator-controlled host
policy, not something this repository automates.

The acceptance baseline is Ubuntu 24.04 LTS and Ubuntu 26.04 LTS, for server and
desktop installations. Debian-family detection remains available, but every
production promotion must still pass the repository's real KVM/Incus acceptance
matrix on the exact host release.

Before APT changes anything, bootstrap verifies:

```bash
dpkg --audit
sudo apt-get check
test -x /usr/bin/cp
test -x /usr/bin/mv
test -x /usr/bin/rm
```

If the configured candidate would upgrade an active Incus daemon, the script
lists running instances and exits. Stop them during scheduled downtime, or set
`VDM_ALLOW_INCUS_UPGRADE_WITH_RUNNING_INSTANCES=true` for that one explicitly
approved run.

The platform never installs or removes `gnu-coreutils`,
`coreutils-from-uutils`, or an alternative `dd`; it never creates a systemd
`PATH` override for Incus.

## Incus authority

Incus administration is root-equivalent. Bootstrap adds the invoking operator
to `incus-admin` only when direct access is absent, completes that one bootstrap
through its explicit privileged path, and asks the operator to log out and back
in. All other commands require direct access by default. They do not reinterpret
a daemon, socket or configuration failure as permission to run `sudo incus`.

For a deliberately privileged one-off invocation, set
`VDM_INCUS_USE_SUDO=true`. Non-interactive use requires an already configured,
narrowly scoped non-interactive sudo policy; the scripts never wait for a
password prompt in CI or a system service.

## Expiry service trust boundary

`install-host-units.sh` copies only the reaper, its shared library and required
non-secret manifests into `/usr/local/libexec/vdm-opencode`, owned by root. It
also writes the selected project name to
`/etc/vdm-opencode-platform/reaper.env` and validates the installed units with
`systemd-analyze verify`.

The timer therefore never gives a user-writable Git checkout a root execution
path. `ProtectHome=true` remains enabled. The service is restricted to the
Incus Unix socket family, has no Linux capabilities or writable home path, and
receives only the Incus runtime and private state paths it needs.

## Network ownership

The workload project has:

```yaml
features.networks: "false"
restricted.networks.access: vdm-buildbr0,vdm-agentbr0
```

The bridges and their ACLs live in the Incus `default` project and carry:

```yaml
user.vdm.managed: "true"
user.vdm.platform: vdm-opencode-platform
```

`apply-incus.sh` refuses to overwrite a same-named network or ACL without those
markers. Before creating a bridge, it also rejects overlapping host routes for
`10.248.17.0/24` or `10.248.18.0/24`.

Older repository revisions created the bridges inside `vdm-agents`. The apply
script can migrate that layout only when the project contains no instances and
owns no unrelated networks or ACLs. Otherwise it stops and lists the blocker;
it never deletes an instance to force a migration.

All ACL rules explicitly use `state: enabled`, avoiding version-dependent empty
state parsing. Ingress stays empty and the NIC default ingress/egress actions
stay `reject`.

## Bridge networking, not OVN

Both networks are native Incus `bridge` networks with NAT, DHCP and DNS. This
layout does not install or require Open vSwitch, `ovn-central`, `ovn-host`, or
the OVN database sockets.

Verify the applied state:

```bash
incus project get vdm-agents features.networks
incus --project default network show vdm-buildbr0
incus --project default network show vdm-agentbr0
incus --project default network acl show vdm-build
```

The first command must print `false`. Each network and ACL must show
`user.vdm.platform: vdm-opencode-platform`.

## Docker coexistence

The repository does not modify Docker, nftables, iptables, UFW, or the
`DOCKER-USER` chain. Docker can set the global forwarding policy to `drop`,
which may block Incus bridge egress. Diagnose this separately:

```bash
sysctl net.ipv4.conf.all.forwarding
sudo iptables -S FORWARD
sudo iptables -S DOCKER-USER 2>/dev/null || true
```

Choose one of the Incus-documented host policies deliberately: configure
Docker's `ip-forward-no-drop`, enable forwarding before Docker starts, or add
persistent bridge-specific egress rules. Do not let a project bootstrap choose
between those system-wide policies automatically. See the
[Incus firewall documentation](https://linuxcontainers.org/incus/docs/main/howto/network_bridge_firewalld/#prevent-connectivity-issues-with-incus-and-docker).

## Publication and failure handling

The builder publishes the verified stopped instance directly. It does not make
a `sanitized` snapshot, and the launcher does not make a `factory` snapshot.
This avoids an unnecessary full raw-disk copy on the `dir` storage driver.

On failure, the exact managed build VM is stopped and retained. The next
identical build resumes it; `--clean` deletes only a checkpoint whose platform,
variant and fingerprint ownership metadata all match. No broad project or host
cleanup is performed.
