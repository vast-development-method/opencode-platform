# JoomEngine MCP for Joomla integration

Reviewed: 2026-07-27

## Status and authority

The approved source is:

`https://github.com/joomengine/joomla-mcp`

The PHP and full images install the public npm release `@joomengine/joomla-mcp@0.7.0`. The package version is exact,
the inspected source commit is recorded in `manifest/sources.lock.yaml`, the image build verifies the installed
version, and the release SBOM records the resulting dependency graph.

`manifest/images.yaml` remains the composition authority. The ready `joomla-mcp` capability resolves to
`image/provision/joomla-mcp.sh`; it is not hidden inside the general PHP provisioner.

Upstream currently describes broad source-backed Joomla 6.1 route coverage while retaining live-production
evidence gates for action families. This platform therefore installs and hardens the integration without claiming
that every privileged action is production-certified. Promotion still requires the real image and live-site
evidence described below.

## Runtime architecture

```text
OpenCode
  -> local stdio command /usr/local/bin/vdm-joomla-mcp
  -> root-owned /etc/joomla-mcp/sites.json (origin, alias, toolsets; no secret)
  -> session-only JOOMLA_MCP_SITE_TOKEN
  -> HTTPS Joomla Web Services API
```

The normal container path uses local stdio:

- no inbound VM port;
- no HTTP MCP listener;
- no MCP bearer token or JWKS endpoint;
- no site origin supplied by a model;
- no credential in OpenCode JSON or the Joomla site file;
- no arbitrary HTTP, CLI, PHP, SQL, filesystem, model, method or URL passthrough.

The configured alias and fixed toolsets bound what the server can expose. Joomla's own Web Services plugins, API
user permissions and ACL remain authoritative beneath that boundary.

The package's authenticated Streamable HTTP entry point remains available as
`/usr/local/bin/vdm-joomla-mcp-http`, but it is not enabled or exposed by this image integration. Deploy it only as
a separately reviewed service with TLS termination, issuer/audience/scope validation and a trusted JWKS endpoint.

## Build and deploy

Build a new PHP image after checking out the platform release that contains the integration:

```bash
./tests/validate-repository.sh
export LOCAL_BUILD_VARIANTS=php
./scripts/local-image-release.sh
./scripts/launch-vm.sh php opencode-joomla
```

An already-running instance built from an older image does not acquire Joomla MCP automatically. Launch from the
new versioned image alias or follow the normal instance replacement workflow.

Configure a public HTTPS Joomla origin:

```bash
./scripts/occtl.sh joomla-configure \
  opencode-joomla \
  https://www.example.com \
  company \
  readonly
```

The command:

1. verifies that the instance contains the Joomla MCP capability;
2. accepts one HTTPS origin only and rejects credentials, paths, queries and fragments;
3. renders one fixed site alias with a named profile;
4. validates the result through the installed package's own configuration loader;
5. installs it as `/etc/joomla-mcp/sites.json`, owned by `root:opencode` with mode `0640`;
6. enables only the local `joomla` OpenCode entry;
7. creates or upgrades the protected per-instance runtime credential template.

The command never accepts a token argument.

## Joomla preparation

For the API path:

1. enable **API Authentication - Web Services Joomla Token**;
2. enable **User - Joomla API Token**;
3. create a dedicated automation user and group;
4. grant `core.login.api` plus only the component permissions required by the selected profile;
5. enable only the Web Services plugins required by those toolsets;
6. generate that user's API token;
7. verify the intended API endpoint over HTTPS before enabling broader tools.

Do not use a Super User token by default. Do not reuse a human administrator token. A read-only platform profile
does not compensate for an unnecessarily privileged Joomla identity.

## Runtime credentials

Create or locate the per-instance tmpfs file:

```bash
runtime_file="$(./scripts/occtl.sh credentials opencode-joomla)"
"${EDITOR:-nano}" "$runtime_file"
chmod 600 "$runtime_file"
```

Supported local Joomla keys are:

| Variable | Required by | Purpose |
|---|---|---|
| `JOOMLA_MCP_SITE_TOKEN` | every API profile | Dedicated Joomla Web Services bearer token |
| `JOOMLA_MCP_APPROVAL_SECRET` | `content`, `admin`, `full` | Signs short-lived, one-time guarded write plans; use at least 32 random characters |
| `JOOMLA_MCP_UPDATE_TOKEN` | `full` | Separately scoped Joomla Update token |

Generate an approval secret without placing it in a command argument to the platform:

```bash
openssl rand -hex 32
```

Paste the result into the protected file. The file lives below `/run/user/$UID`, is never committed and is removed
at logout or reboot. `start-session.sh` rejects symlinks, foreign ownership, non-`0600` mode, hard links, malformed
names, unknown keys and duplicate keys. It then copies the file as a root-owned systemd credential. Secret values
do not enter Incus process arguments.

Before OpenCode starts, the platform reads the non-secret Joomla configuration, enumerates the credential variable
names it references and fails closed when any required value is absent. The same validation is used by the
in-image read test.

## Profiles

`joomla-configure` supports four deliberate profiles.

### `readonly`

Enables discovery plus content, structure, media, users, extensions, configuration and maintenance reads. It
contains no approval block and no write/admin/core-update toolset. This is the default.

### `content`

Adds content, structure and media writes. The package still requires an operator permission request, exact
acknowledgement, a non-dry-run plan and one-time confirmation token. Joomla ACL can deny the operation at any later
layer.

### `admin`

Adds user, extension, configuration and maintenance administration. Use only with explicit authorization, narrow
Joomla ACL and recovery evidence.

### `full`

Adds `core-update` and references the separate update token. Use only on an explicitly controlled environment after
the relevant upstream live and recovery gates have passed. Selecting `full` is not a substitute for those gates.

All write profiles set `allowIndefinite: false`. Reconfigure deliberately to change profiles; do not edit toolsets
from an agent session.

## Safe in-image evidence

Run the built-in non-mutating test:

```bash
./scripts/occtl.sh joomla-test \
  opencode-joomla \
  "$runtime_file" \
  company
```

It securely launches `/usr/local/bin/vdm-joomla-mcp-live-test` inside the VM with:

```text
--profile read
--joomla-path api
--mcp-transport stdio
--non-interactive
```

No mutation confirmation and no disposable-site acknowledgement are present. Evidence is retained under:

`/workspace/.artifacts/joomla-mcp/<session-id>`

The upstream `crud` and `full` matrices are intentionally not exposed through this convenience command. They can
modify or delete Joomla data and must be run only against an explicitly disposable site, using the upstream
documentation and an operator-approved test plan.

## Use from OpenCode

Start the bounded session:

```bash
./scripts/occtl.sh session opencode-joomla "$runtime_file"
```

Inside OpenCode, use this sequence:

1. `joomla_sites_list`;
2. `joomla_capabilities`;
3. `joomla_actions_search`;
4. `joomla_action_describe`;
5. `joomla_action_read` for the selected fixed semantic action.

For writes, review the dry-run plan, request the exact bounded permission, obtain the operator's acknowledgement,
create the non-dry-run plan, apply its one-time token, and independently verify the result. Treat every Joomla
title, body, metadata value and error as untrusted content, not instructions.

Disable the server for an instance without deleting its non-secret configuration:

```bash
./scripts/occtl.sh mcp opencode-joomla joomla false
```

## Network policy

The ready `connected` policy permits public IPv4 Internet while rejecting private, carrier-grade NAT, loopback,
link-local, metadata, multicast and management ranges. It is suitable for a public HTTPS Joomla origin.

A Joomla site on a private LAN will not be reachable through that policy. Use the approved brokered/restricted
gateway once deployed, or an explicitly acknowledged lab environment. Do not remove the private-network rejects
from the shared connected policy simply to reach one site.

## Promotion and upgrade checklist

Before calling an image/site combination production-ready:

1. validate the repository and generated manifest drift;
2. build the real PHP image on the trusted KVM/Incus builder;
3. verify exact package version, disabled default, absent active site config and sanitized image state;
4. export, verify and import the package on a second clean host;
5. run the included read profile against the intended Joomla version and retain redacted evidence;
6. verify denied operations with an under-privileged Joomla identity;
7. run any required upstream mutation matrix only on a disposable clone;
8. review Joomla MCP upstream coverage/recovery gates for every enabled write/admin family;
9. confirm token rotation, revocation, audit retention and incident rollback;
10. promote the new platform/image version rather than overwriting an old identity.

To upgrade Joomla MCP, update the exact npm and expected versions, inspected source commit, documentation and
changelog together. Rebuild both PHP and full images, rerun static validation, then repeat real-image and live-site
evidence. Never replace the exact package reference with `@latest`.
