# VDM OpenCode Platform

Reusable, versioned OpenCode worker VMs for Incus. Ductor deploys persistent
services and dedicated worker pools; this repository owns the worker image
supply chain, standalone sessions, native Joomla/JCB MCP connections and durable
company-context handoffs.

## Build and launch

Six Ubuntu 24.04 variants remain available: `base`, `php`, `python`, `cpp`,
`typescript` and `full`. `manifest/images.yaml` owns composition, resource sizes
and policies. Node is pinned and checked against the actual runtime; every
variant can connect to the native remote Joomla/JCB MCP service. No legacy
TypeScript Joomla server is installed in the guest.

```bash
cp .env.example .env
make ci
./scripts/bootstrap-host.sh
./scripts/apply-incus.sh
LOCAL_BUILD_VARIANTS=php ./scripts/local-image-release.sh
./scripts/launch-vm.sh php opencode-joomla
```

Host bootstrap supports Ubuntu 24.04/26.04. It preserves package sources and
Docker firewall rules, refuses unsafe Incus upgrades with running instances,
and treats `incus-admin` as root-equivalent. Agent VMs never receive that
membership or the controller's Incus private key. Build limits reserve host
capacity; failed builds retain resumable diagnostics. See
[local builds](docs/local-image-builds.md) and [host safety](docs/host-and-network-safety.md).

## Connect the current Joomla and JCB MCP

Use [JoomEngine's MCP image](https://github.com/octoleo/joomengine), such as its
`latest-mcp` selection, resolved to an approved digest by the deployment.
Ordinary `latest` does not contain MCP. Keep Joomla, its database and its MCP
service in a persistent service VM. Replacing a Docker image does not install or
upgrade MCP in an existing Joomla volume; use the explicit migration operation.

The server is [mcp_component](https://github.com/joomengine/mcp_component), with
its authenticated endpoint at `/api/index.php/v1/joomengine-mcp`. JCB integration
is already implemented: discover installed capabilities, use native reviewed
plans and confirmations, follow durable jobs and retrieve verified artifacts.
Do not duplicate its catalogue or permission system in an agent wrapper.

Configure a site using its real HTTPS base URL or full MCP endpoint:

```bash
./scripts/occtl.sh joomla-configure opencode-joomla https://joomla.example.com company readonly
runtime_file="$(./scripts/occtl.sh credentials opencode-joomla)"
"${EDITOR:-nano}" "$runtime_file"
./scripts/occtl.sh joomla-test opencode-joomla "$runtime_file" company
./scripts/occtl.sh session opencode-joomla "$runtime_file"
```

Set `JOOMLA_MCP_SITE_TOKEN` to the dedicated Joomla API identity's token. Other
site aliases have separate credential references. `readonly` describes the
intended server identity: Joomla ACL actually enforces permissions. OpenCode
connects directly using Streamable HTTP, token headers and `oauth: false`.

Ductor can provision the identity and return a protected client document:

```bash
./scripts/occtl.sh joomla-import opencode-joomla /secure/joomla-client.json
```

For OpenBao-managed credentials, use `credentials-fetch INSTANCE CONFIG_JSON`;
see [credential configuration](docs/credentials-and-brokers.md). Tokens never
belong in an image, Git, OpenCode JSON, command arguments or company documents.

## Private services and Ductor

The standard connected policy blocks private destinations. For a standalone
worker, `network-configure INSTANCE SERVICE_NETWORK_JSON` installs exact service
IP/port routes with default-deny ingress and egress. Ductor-owned pools use
Ductor's network configuration. See [private routes](docs/service-network.md).

Publish and verify an image package, then obtain its actual Ductor identity:

```bash
./scripts/occtl.sh ductor-image build/packages/0.4.0-rc.1/amd64/php vdm-agents
```

The command verifies the supplied package rather than inventing fingerprints.
Use the emitted identity in Ductor's pool configuration. Crabbox owns workers it
creates; do not attach the standalone expiry metadata to those workers. Shared
services and company knowledge continue operating when Ductor is offline.

## Company standards and review handoffs

Maintain company objectives, standards, preferred technologies and accepted
project findings in an independent Git repository. Commit a
`company-context.json` listing the instruction documents, then synchronize a
reviewed revision:

```bash
./scripts/occtl.sh company-sync opencode-joomla /srv/company-standards
./scripts/occtl.sh handoff-export opencode-joomla /srv/reviews/task-001 review/outcome.md
```

The worker loads a root-owned, hash-verified snapshot with commit provenance.
Session startup verifies it; session expiry cannot delete the authoritative
repository. Export selects explicit files into durable storage, checks paths
and common credential patterns, and records hashes for the next reviewer.
[Company context and handoffs](docs/company-context.md) defines the complete flow.

## Verification and operation

`make ci` runs repository, security, runtime and package round-trip checks. The
native HTTP tests exercise real TLS transport, discovery pagination, permission
failures and session recovery without a model-provider account. The companion
Ductor integration exercises a real Joomla/MariaDB deployment and native identity.
Target-host Incus, private routing and controller-off acceptance must also run on
the actual deployment; see [integration contract](docs/integration-contract.md)
and [known limitations](docs/known-limitations.md).

Other guides: [image variants](docs/image-variants.md),
[MCP catalogue](docs/mcp-catalog.md), [Joomla integration](docs/joomla-mcp-study.md),
[JCB workflow](docs/jcb-mcp-roadmap.md), [versioning](docs/versioning-and-promotion.md).

## Licence

Copyright (C) 2026 Vast Development Method. Repository source is GPL-3.0-only.
Generated images contain independently licensed software recorded by the SBOM.
