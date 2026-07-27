# Credentials and brokers

## Initial mode

`start-session.sh` injects an allowlisted environment file into one bounded
systemd unit and redirects OpenCode's data directory to guest tmpfs. On exit it
deletes the guest credential and runtime directory.

The host file is created by:

```bash
./scripts/occtl.sh credentials INSTANCE
```

It lives under `/run/user/$UID/vdm-opencode`, must be a regular single-link file
owned by the caller with mode `0600`, and is never passed as a string of secret
values to `incus exec`.

This reduces persistence but does not hide a token from the process that must
use it. Therefore all injected tokens must be:

- short-lived where the upstream supports leases;
- narrowly scoped;
- revocable;
- budget-limited where applicable;
- unusable outside approved services.

Unknown names, duplicate names, carriage returns and malformed lines fail
closed on both the host and guest side.

## Local Joomla MCP path

The PHP and full images launch JoomEngine MCP for Joomla over local stdio. That
path does not expose an inbound MCP endpoint and does not use
`JOOMLA_MCP_URL`/`JOOMLA_MCP_TOKEN`.

The site definition contains only the fixed HTTPS origin, alias, toolsets and
credential variable names. The protected session supplies:

- `JOOMLA_MCP_SITE_TOKEN` for the dedicated Joomla Web Services API identity;
- `JOOMLA_MCP_APPROVAL_SECRET` only when guarded writes are configured;
- `JOOMLA_MCP_UPDATE_TOKEN` only when the explicit full/core-update profile is configured.

`start-session.sh` reads the non-secret site configuration and refuses to start
when a referenced credential is absent. The built-in read-only live test uses
the identical systemd credential path. Neither helper accepts a token as a
command-line argument.

## Corporate mode

A trusted broker host should retain long-lived upstream credentials and expose only capabilities:

- LLM gateway virtual keys with model, rate and spend limits;
- GitHub/Gitea MCP sessions limited to selected repositories and operations;
- Nextcloud MCP sessions limited to selected users, apps and tagged folders;
- scoped Joomla API identities or short-lived equivalents limited to approved
  sites and component permissions;
- future JCB integration only after its release gates pass.

The VM must never receive a Vaultwarden or OpenBao identity capable of reading all upstream secrets.

## Provider capability paths

Autonomous sessions use one route for each provider:

- OpenAI API, Anthropic/Claude API, Google Gemini API and xAI/Grok API:
  OpenBao-held upstream credential → LiteLLM policy route → short-lived session
  virtual key → root-owned guest relay → tokenless local OpenCode endpoint.
- Local models: the gateway exposes approved OpenAI-compatible inference
  routes only. Model administration and the host Ollama/API port remain
  unreachable from agent networks.
- ChatGPT subscription login: interactive developer sessions may use
  OpenCode's supported login inside tmpfs. It is not an autonomous production
  credential path.
- GitHub: the gateway mints a GitHub App installation token scoped to selected
  repositories and operations.
- Gitea and remote MCP: the gateway retains the service credential and checks
  session identity, repository, tool, read/write level and expiry per request.
- Joomla: the present local stdio path receives a dedicated Joomla bearer token
  through the bounded session. A future broker may exchange site/session
  identity for a shorter-lived site capability, but must not broaden Joomla ACL.
- VPS access: the VM creates an ephemeral key; OpenBao SSH CA signs the public
  key for 10–15 minutes; the network policy permits only the audited bastion.

The current environment-file bridge is transitional. It uses systemd
credentials and avoids secret values in host process arguments, but child
commands can still exercise or inspect exported session variables. Release
promotion requires the tokenless root-owned relay described above for provider
paths where such a relay is practical.

## OpenBao

OpenBao is suitable for machine identity, short leases, revocation and audit.
The agent should not query broad secret paths directly. A broker exchanges an
OpenBao-authenticated service identity for downstream capability tokens.

For Joomla, preserve separate authorities for the normal API identity and
Joomla Update. Do not issue a single universal token merely because the
platform supports several toolsets.

## Vaultwarden

Vaultwarden remains useful for human-controlled bootstrap and recovery secrets.
Do not give the autonomous VM a universal Vaultwarden account.

## Runtime file

Create or upgrade it under host tmpfs:

```bash
runtime_file="$(./scripts/occtl.sh credentials INSTANCE)"
"${EDITOR:-nano}" "$runtime_file"
chmod 600 "$runtime_file"
```

The script refuses unsafe file types and preserves existing values while adding
new allowlisted Joomla keys during a platform upgrade.
