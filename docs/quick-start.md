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

## 5. Configure JoomEngine MCP for Joomla

The PHP and full images contain the exact package recorded in `manifest/toolchain.env`. Configure one HTTPS Joomla
origin; this writes only a root-owned, non-secret site definition and enables the local stdio entry:

```bash
./scripts/occtl.sh joomla-configure \
  opencode-llewellyn \
  https://www.example.com \
  company \
  readonly
```

Profiles are explicit:

- `readonly` is the default and contains no write/admin toolset;
- `content` adds guarded content, structure and media writes;
- `admin` adds guarded user, extension, configuration and maintenance administration;
- `full` additionally exposes `core-update` and requires a separately scoped update token.

Do not select `content`, `admin`, or `full` merely to make a read test pass. Joomla ACLs, enabled Web Services
plugins, the package's permission grants and its one-time plans remain independent controls.

## 6. Prepare runtime-only credentials

```bash
runtime_file="$(./scripts/occtl.sh credentials opencode-llewellyn)"
"${EDITOR:-nano}" "$runtime_file"
chmod 600 "$runtime_file"
```

For the normal read-only profile, set only:

```dotenv
JOOMLA_MCP_SITE_TOKEN=the-dedicated-joomla-api-token
```

The file is under `/run/user/$UID`, which is tmpfs. The script rejects symlinks, foreign ownership, hard links,
unexpected names and duplicate variables. Tokens are copied through systemd credentials and never placed in an
Incus command argument.

A guarded write profile also requires a random approval secret of at least 32 characters:

```bash
openssl rand -hex 32
```

Place the result in `JOOMLA_MCP_APPROVAL_SECRET`. The `full` profile additionally requires
`JOOMLA_MCP_UPDATE_TOKEN`; do not reuse the normal Joomla API token.

## 7. Run the safe in-image Joomla test

```bash
./scripts/occtl.sh joomla-test \
  opencode-llewellyn \
  "$runtime_file" \
  company
```

This executes `joomla-mcp-live-test` inside the VM with `--profile read`, Joomla API transport and stdio MCP
transport. It has no mutation confirmation or disposable-site flag and writes redacted evidence under
`/workspace/.artifacts/joomla-mcp/<session-id>`.

The upstream `crud` and `full` live matrices are intentionally not wrapped by this convenience command. Run those
only against an explicitly disposable Joomla site after reading the upstream live-testing documentation.

## 8. Enable other required MCP servers

Joomla was enabled by `joomla-configure`. Other integrations remain separate:

```bash
./scripts/occtl.sh mcp opencode-llewellyn github true
./scripts/occtl.sh mcp opencode-llewellyn gitea true
./scripts/occtl.sh mcp opencode-llewellyn playwright true
```

Enabling a local MCP now fails if its executable is absent. Enabling Joomla also fails if the target configuration
is absent or invalid.

## 9. Start OpenCode

```bash
./scripts/occtl.sh session opencode-llewellyn "$runtime_file"
```

The session validates every credential name referenced by the Joomla site file before starting OpenCode. Inside
OpenCode, call `joomla_sites_list`, then `joomla_capabilities`, `joomla_actions_search` and
`joomla_action_describe` before executing an action.

The guest's OpenCode data directory lives under `/run` for this session.

## 10. Configure model roles

After provider access is working:

```bash
./scripts/configure-models.sh opencode-llewellyn
```

Use exact IDs shown by `opencode models`.

## 11. Normal work

Clone only repositories assigned to the session account, create an agent branch, run tests and open a pull request.
Do not merge or release directly from an autonomous session.
