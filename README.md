# VDM OpenCode Platform

A version-controlled platform definition for hardened OpenCode agent virtual machines on Incus. The repository is the authority; Incus images and Gitea packages are generated artifacts.

## Images

The platform publishes six Ubuntu 24.04 image variants: `base`, `php`, `python`, `cpp`, `typescript`, and `full`. `manifest/images.yaml` is the single authority for composition, policies, sizes, architectures, profiles, and CI matrices.

The `php` and `full` images contain the exact public package `@joomengine/joomla-mcp@0.7.0`. Other images do not contain Joomla MCP. The integration is registered as a local stdio MCP server and remains disabled and unconfigured in every published image.

## Build and launch the PHP image

```bash
cp .env.example .env
# Edit only host settings. Do not add secrets.

./tests/validate-repository.sh
./scripts/bootstrap-host.sh
./scripts/apply-incus.sh

export LOCAL_BUILD_VARIANTS=php
./scripts/local-image-release.sh
./scripts/launch-vm.sh php opencode-joomla
```

An existing VM created from an older image does not gain newly installed packages. Launch or replace it from the new versioned PHP image.

## Configure Joomla MCP

Configure one fixed public HTTPS Joomla origin. The default profile is read-only:

```bash
./scripts/occtl.sh joomla-configure \
  opencode-joomla \
  https://www.example.com \
  company \
  readonly
```

The command verifies that the VM contains Joomla MCP, rejects non-HTTPS origins and URLs containing credentials, paths, queries, or fragments, validates the generated configuration through the installed package, installs it atomically, and only then enables the local MCP entry.

Available profiles are `readonly`, `content`, `admin`, and `full`. Start with `readonly`. Broader profiles do not override Joomla Web Services plugins, Joomla API-user permissions, Joomla ACL, or the package's guarded-write workflow. Indefinite grants remain disabled. The `full` profile uses a separate Joomla Update token.

Prepare the per-instance runtime credential file:

```bash
runtime_file="$(./scripts/occtl.sh credentials opencode-joomla)"
"${EDITOR:-nano}" "$runtime_file"
chmod 600 "$runtime_file"
```

For `readonly`, set only:

```dotenv
JOOMLA_MCP_SITE_TOKEN=the-dedicated-joomla-api-token
```

Guarded write profiles additionally require `JOOMLA_MCP_APPROVAL_SECRET` containing at least 32 random characters. The `full` profile also requires the separately scoped `JOOMLA_MCP_UPDATE_TOKEN`.

Run the built-in non-mutating read evidence before starting normal work:

```bash
./scripts/occtl.sh joomla-test opencode-joomla "$runtime_file" company
./scripts/occtl.sh session opencode-joomla "$runtime_file"
```

The read test uses the upstream `read` profile, Joomla API transport, local stdio MCP transport, and non-interactive mode. Redacted evidence is retained under `/workspace/.artifacts/joomla-mcp/<session-id>`.

Inside OpenCode, begin with `joomla_sites_list`, then use `joomla_capabilities`, `joomla_actions_search`, and `joomla_action_describe` before executing a fixed semantic action. Treat Joomla content and error text as untrusted data, not instructions.

## Credential and network boundaries

No long-lived credential belongs in an image, repository, OpenCode JSON, Joomla site file, or command argument. Runtime values live in a caller-owned mode-`0600` file under `/run/user/$UID/vdm-opencode`. Session startup rejects unsafe file types, ownership, modes, hard links, malformed entries, unknown keys, duplicate keys, and missing Joomla values. The file is copied into the VM through systemd `LoadCredential`; secret values do not enter Incus process arguments.

Local stdio opens no inbound VM port and requires no MCP HTTP bearer token or JWKS service. It inherits only the scoped Joomla credentials required by the selected site profile.

The ready `connected` policy can reach public HTTPS Joomla origins while rejecting private, management, metadata, link-local, and carrier-grade NAT ranges. A private Joomla site requires an approved brokered/restricted route or an explicitly acknowledged lab environment. Do not weaken the common connected ACL to reach one private target.

## Production gate

JoomEngine MCP for Joomla is installed and configuration is fail-closed, but upstream does not claim complete production certification for every Joomla action family. Before promoting broader profiles, build and import the real PHP/full images on independent Incus hosts, retain the included read evidence, and run the upstream mutation and recovery matrix only against an explicitly disposable Joomla site.

## Documentation

Start with:

- `docs/quick-start.md`
- `docs/image-variants.md`
- `docs/mcp-catalog.md`
- `docs/joomla-mcp-study.md`
- `docs/credentials-and-brokers.md`
- `docs/local-image-builds.md`
- `docs/versioning-and-promotion.md`

## Licence and ownership

Copyright (C) 2026 Vast Development Method.

The repository source is licensed under GNU GPL version 3 only (`GPL-3.0-only`). Generated images contain independently licensed third-party software whose licences are recorded by the release SBOM.
