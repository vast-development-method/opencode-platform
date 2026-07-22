# VDM OpenCode Platform

A company-wide, version-controlled platform definition for hardened OpenCode agent virtual machines on Incus.

The repository is the authority. Incus images and package registries contain generated artifacts.

## What this repository provides

- A common Ubuntu 24.04 VM base and five variants: `base`, `php`, `python`, `cpp`, `typescript`, and `full`.
- Repeatable Incus projects, networks, ACL scaffolding, profiles, image builds and instance launches.
- OpenCode agents for orchestration, architecture, implementation, testing, review, security, browser QA,
  documentation, PHP/Joomla, Python, C/C++, and TypeScript.
- Local Git MCP and Playwright browser MCP integration.
- Disabled-by-default remote MCP definitions for GitHub, Gitea, Nextcloud, the future VDM Joomla MCP, future JCB
  MCP, and speech-to-text.
- Runtime-only credential handling under the guest's `/run` tmpfs.
- Gitea Generic Package publishing and GitHub Actions artifact downloads.
- Image sanitisation and secret-scanning tests.

## Recommended image strategy

| Image | Primary use | Browser MCP |
|---|---|---|
| `base` | Repository analysis, documentation, light automation | Disabled |
| `php` | Joomla, JCB and PHP services | Enabled |
| `python` | APIs, automation, MCP services and data tooling | Disabled |
| `cpp` | Native Linux, graphics and systems development | Disabled |
| `typescript` | Web applications, Node.js and browser automation | Enabled |
| `full` | Mixed-language platform work | Enabled |

Use specialised images for ordinary work and `full` only for genuinely mixed-language projects.

## First deployment

```bash
cp .env.example .env
./tests/validate-repository.sh
./scripts/bootstrap-host.sh
./scripts/apply-incus.sh
./scripts/build-image.sh php
./scripts/launch-vm.sh php opencode-llewellyn
./scripts/start-session.sh opencode-llewellyn
```

Do not put secrets in `.env`. Runtime tokens belong in a mode-`0600` session file under
`/run/user/$UID/vdm-opencode/`.

## Build and distribution

The image workflow runs on a self-hosted runner labelled `self-hosted`, `linux`, and `incus`. Manual runs and
version tags build all variants and upload downloadable GitHub Actions artifacts. Tagged builds can additionally
publish the same files to Gitea Generic Packages when the Gitea publishing variables and secret are configured.

See `docs/github-gitea-roadmap.md` for the hosting choices and migration path.

## MCP policy

- Gitea MCP remains a supported, disabled-by-default first-party integration.
- `https://github.com/vast-development-method/joomla-mcp` is the only approved Joomla MCP source and remains
  disabled until its first reviewed release.
- JCB MCP remains deferred and disabled until the internal implementation has a repository and approved release.
- No long-lived MCP credential belongs in an image.

## Release limitations

The workflow and repository structure are ready for repeatable validation and image packaging, but production
promotion remains blocked until every `REVIEW_AND_PIN` and floating `@latest` reference is replaced with an
approved immutable version and checksum. See `docs/versioning-and-promotion.md`.

## Documentation

Start with:

- `docs/quick-start.md`
- `docs/architecture.md`
- `docs/security-model.md`
- `docs/image-variants.md`
- `docs/mcp-catalog.md`
- `docs/github-gitea-roadmap.md`
- `docs/gitea-packages.md`
- `docs/versioning-and-promotion.md`
- `docs/known-limitations.md`
