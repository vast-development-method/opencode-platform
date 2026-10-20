# Quick start

## 1. Clone and validate

```bash
git clone https://github.com/vast-development-method/opencode-platform.git
cd opencode-platform
cp .env.example .env
make ci
```

Use `GITEA_BASE_URL` and `INCUS_STORAGE_POOL` in `.env` when the defaults do not match the host. Do not place
secrets in `.env`.

The host path supports Ubuntu 24.04 LTS and 26.04 LTS, on server and desktop
installations. The built VM remains Ubuntu 24.04 LTS on either host.

## 2. Prepare Incus

```bash
./scripts/bootstrap-host.sh
./scripts/ci/check-incus-runner.sh php
```

Bootstrap already applies the Incus resources and installs the expiry timer;
running `apply-incus.sh` again is safe but unnecessary.

The bootstrap fails before package installation when APT/dpkg is inconsistent
or essential core utilities are missing. It upgrades Incus only to the newest
candidate in repositories already configured by the operator. It does not add
a third-party repository, replace core utilities, install OVN/Open vSwitch, or
change Docker/firewall configuration.

When needed, bootstrap adds the invoking account to `incus-admin`. This group is
root-equivalent. Log out and back in after the command reports that membership
was added; normal platform commands deliberately do not fall back to `sudo`
after an arbitrary Incus failure.

## 3. Build one image

For Joomla/JCB work:

```bash
./scripts/build-image.sh php
```

For web/TypeScript:

```bash
./scripts/build-image.sh typescript
```

The build command repeats the resource preflight before creating anything.
Runtime size profiles are not build profiles: TypeScript normally builds with
4 CPUs and 8 GiB, can safely fall back no lower than 2 CPUs and 6 GiB, and
always preserves the manifest's host-memory and QEMU reserve. Swap is not
required or counted.

If provisioning fails, rerun the same command. The stopped checkpoint resumes
completed stages, and cached Playwright/APT/npm/pip downloads are reused. For a
deliberately clean verification build:

```bash
./scripts/build-image.sh --clean --no-cache typescript
```

Build every variant only on a dedicated builder with sufficient disk space:

```bash
./scripts/build-all-images.sh
```

A platform upgrade that changes the PHP image requires rebuilding and relaunching from the new versioned alias.
Existing instances do not acquire newly installed packages merely because the repository changed.

The verified stopped build VM is published directly. No temporary full-disk
snapshot is created.

The expiry timer executes a root-owned copy under `/usr/local/libexec`; it does
not execute the checkout under the operator's home directory. The unit keeps
home directories hidden and grants write access only to the Incus runtime path
and its private state directory.

## 4. Launch a personal VM

```bash
./scripts/launch-vm.sh php opencode-llewellyn
```

## 5. Configure native Joomla and JCB MCP

All images can connect to the current PHP MCP server. Configure the actual HTTPS
site URL (subdirectories and the full MCP endpoint are supported):

```bash
./scripts/occtl.sh joomla-configure opencode-llewellyn https://joomla.example.com company readonly
```

The dedicated Joomla identity must have the intended native permissions.
`readonly` and `write` are identity intent labels; they do not override Joomla
ACL. The server supplies installed JCB definitions, reviewed plans, confirmations,
durable jobs and artifact retrieval. See [JCB workflow](jcb-mcp-roadmap.md).

For private sites, configure exact routes using `network-configure`; see
[service networking](service-network.md). Shared Joomla services belong outside
the worker VM and remain available after its session expires.

## 6. Supply scoped runtime credentials

```bash
runtime_file="$(./scripts/occtl.sh credentials opencode-llewellyn)"
"${EDITOR:-nano}" "$runtime_file"
```

Set `JOOMLA_MCP_SITE_TOKEN` for the company site. The file remains mode 0600 on
tmpfs; no secret belongs in OpenCode JSON or Incus arguments. Alternatively use
`joomla-import INSTANCE DUCTOR_CLIENT_JSON` for a provisioned identity, or
`credentials-fetch INSTANCE OPENBAO_CONFIG_JSON` for exact KV-v2 references.
[Credential configuration](credentials-and-brokers.md) explains both paths.

## 7. Load company standards and verify the connection

```bash
./scripts/occtl.sh company-sync opencode-llewellyn /srv/company-standards
./scripts/occtl.sh joomla-test opencode-llewellyn "$runtime_file" company
```

Company instructions come from a reviewed Git revision and survive disposable
sessions at their external source. The MCP test performs native HTTPS
initialization and discovery, reads supported non-mutating capabilities, and
stores private evidence under `/workspace/.artifacts/joomla-mcp/`.

## 8. Start work and retain the outcome

```bash
./scripts/occtl.sh session opencode-llewellyn "$runtime_file"
./scripts/occtl.sh handoff-export opencode-llewellyn /srv/reviews/task-001 review/outcome.md
```

Native discovery is authoritative: use available schemas rather than old
TypeScript tool names. Review plans before confirming effectful actions; resume
uncertain work by its execution/job identity rather than blindly retrying writes.
Store accepted decisions in the company/project repository for the next worker.
See [company context](company-context.md) for artifact limits and provenance.

Other MCP services can be enabled individually using `occtl mcp INSTANCE SERVER
true`. Model roles can be selected using `occtl models INSTANCE` and exact IDs
from `opencode models`. Clone only assigned repositories, create an agent branch,
run checks and open a PR; release decisions remain explicit.
