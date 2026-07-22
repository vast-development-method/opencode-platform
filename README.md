# VDM OpenCode Platform

A company-wide, version-controlled platform definition for hardened OpenCode agent virtual machines on Incus.

The repository is the authority. Incus images and Gitea packages are generated artifacts.

## What this repository provides

- A common Ubuntu 24.04 VM base and five image variants: `base`, `php`, `python`, `cpp`, `typescript`, and `full`.
- Repeatable Incus projects, networks, ACL scaffolding, profiles, resource limits, image builds and launches.
- OpenCode agents for orchestration, architecture, implementation, testing, review, security, browser QA,
  documentation, PHP/Joomla, Python, C/C++, and TypeScript.
- Local Git MCP and Playwright browser MCP integration.
- Disabled-by-default remote MCP definitions for GitHub, Gitea, Nextcloud and speech-to-text.
- Runtime-only credential handling under the guest's `/run` tmpfs.
- A reference external broker stack for OpenBao, an LLM gateway and a TLS reverse proxy.
- Provider-correct GitHub Actions and Gitea Actions workflows.
- Downloadable GitHub workflow artifacts, fully local image releases, and durable Gitea Generic Package publication.
- Image sanitisation and secret-scanning tests.
- Host-side voice recording and transcription through any OpenAI-compatible transcription endpoint.

## Recommended image strategy

Use specialised images for normal work and the full image only when a project genuinely crosses languages.

| Image | Primary use | Browser MCP |
|---|---|---|
| `base` | Repository analysis, documentation, light automation | Disabled |
| `php` | Joomla, JCB and PHP services | Enabled |
| `python` | APIs, automation, MCP services and data tooling | Disabled |
| `cpp` | Native Linux, graphics and systems development | Disabled |
| `typescript` | Web applications, Node.js and browser automation | Enabled |
| `full` | Mixed-language platform work | Enabled |

Every image inherits the same security policy and agent framework.

## First deployment

```bash
cp .env.example .env
# Edit only host settings here. Do not add secrets.

./tests/validate-repository.sh
./scripts/bootstrap-host.sh
./scripts/apply-incus.sh
./scripts/build-image.sh php
./scripts/package-image.sh php
./scripts/launch-vm.sh php opencode-llewellyn
./scripts/start-session.sh opencode-llewellyn
```

Inside OpenCode, use `/connect` for ChatGPT Plus where supported by OpenCode. Anthropic subscription reuse is not
configured: use an approved Anthropic API credential or the company LLM gateway. Grok should use the xAI API or
company gateway. Local Llama uses the configured OpenAI-compatible local endpoint.

## Credentials

No long-lived credential belongs in an image.

`start-session.sh` creates a root-owned guest runtime directory under `/run/vdm-opencode-session`, sets
`XDG_DATA_HOME` to that tmpfs location, injects only the current short-lived variables, launches OpenCode, and
deletes the directory on exit. OpenCode provider and MCP OAuth material generated during that session therefore
does not survive a clean VM stop.

For production, point the VM at a trusted external LLM/MCP gateway and issue short-lived, scoped session tokens.

## Important limitations

- The reference broker deployment is a scaffold, not a substitute for a security review.
- Nextcloud MCP is community software and remains disabled until your team pins and audits a chosen implementation.
- Joomla MCP is not installed. The only future integration target is
  `vast-development-method/joomla-mcp`, after its first reviewed release.
- JCB MCP is not installed and will be added only after the internal repository and first reviewed release exist.
- Incus ACLs cannot safely express every hostname-based egress rule. Enforce strict outbound access at a proxy or
  firewall that supports DNS-aware policy.
- Incus packages are architecture-specific and must be produced by a trusted hardware-virtualisation runner.

## Documentation

Start with:

- `docs/quick-start.md`
- `docs/architecture.md`
- `docs/security-model.md`
- `docs/image-variants.md`
- `docs/mcp-catalog.md`
- `docs/provider-integration.md`
- `docs/browser-testing.md`
- `docs/credentials-and-brokers.md`
- `docs/scaling-and-operations.md`
- `docs/local-image-builds.md`\n- `docs/gitea-packages.md`
- `docs/github-and-gitea.md`
- `docs/backup-and-migration.md`
