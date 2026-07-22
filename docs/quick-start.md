# Quick start

## 1. Clone and validate

```bash
git clone https://github.com/vast-development-method/opencode-platform.git
cd vdm-opencode-platform
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

## 4. Launch a personal VM

```bash
./scripts/launch-vm.sh php opencode-llewellyn
```

## 5. Prepare runtime-only variables

```bash
runtime_file="$(./scripts/create-runtime-env.sh opencode-llewellyn)"
editor "$runtime_file"
chmod 600 "$runtime_file"
```

The file is under `/run/user/$UID`, which is tmpfs. Obtain only short-lived scoped tokens from the broker.

## 6. Enable required MCP servers

```bash
./scripts/mcp-toggle.sh opencode-llewellyn github true
./scripts/mcp-toggle.sh opencode-llewellyn gitea true
./scripts/mcp-toggle.sh opencode-llewellyn playwright true
```

Joomla and JCB are intentionally absent and cannot be enabled until their VDM-owned releases are approved.

## 7. Start OpenCode

```bash
./scripts/start-session.sh opencode-llewellyn "$runtime_file"
```

The guest's OpenCode data directory lives under `/run` for this session.

## 8. Configure model roles

After provider access is working:

```bash
./scripts/configure-models.sh opencode-llewellyn
```

Use exact IDs shown by `opencode models`.

## 9. Normal work

Clone only repositories assigned to the session account, create an agent branch, run tests and open a pull request.
Do not merge or release directly from an autonomous session.
