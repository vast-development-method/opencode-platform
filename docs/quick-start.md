# Quick start

## 1. Clone and validate

```bash
git clone https://github.com/vast-development-method/opencode-platform.git
cd opencode-platform
cp .env.example .env
./tests/validate-repository.sh
```

Use `GITEA_BASE_URL` and `INCUS_STORAGE_POOL` in `.env` when the defaults do not match the host. Do not place
secrets in `.env`.

## 2. Prepare Incus

```bash
./scripts/bootstrap-host.sh
./scripts/apply-incus.sh
./scripts/ci/check-incus-runner.sh
```

## 3. Build one image

For Joomla/JCB work:

```bash
./scripts/build-image.sh php
```

For web/TypeScript:

```bash
./scripts/build-image.sh typescript
```

Build every variant only on a dedicated builder with sufficient disk space:

```bash
./scripts/build-all-images.sh
```

A platform upgrade that changes the PHP image requires rebuilding and relaunching from the new versioned alias.
Existing instances do not acquire newly installed packages merely because the repository changed.

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
