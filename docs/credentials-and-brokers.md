# Credentials and brokers

## Initial mode

`start-session.sh` injects environment values into one OpenCode process and redirects OpenCode's data directory to
guest tmpfs. On exit it deletes that guest runtime directory.

This reduces persistence but does not hide a token from the agent process. Therefore all injected tokens must be:

- short-lived;
- narrowly scoped;
- revocable;
- budget-limited where applicable;
- unusable outside approved services.

## Corporate mode

A trusted broker host should retain long-lived upstream credentials and expose only capabilities:

- LLM gateway virtual keys with model, rate and spend limits;
- GitHub/Gitea MCP sessions limited to selected repositories and operations;
- Nextcloud MCP sessions limited to selected users, apps and tagged folders;
- future VDM-owned Joomla/JCB integrations, added only after their release gates pass.

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
- VPS access: the VM creates an ephemeral key; OpenBao SSH CA signs the public
  key for 10–15 minutes; the network policy permits only the audited bastion.

The current environment-file bridge is transitional. It now uses systemd
credentials and avoids secret values in host process arguments, but child
commands can still exercise or inspect exported session variables. Release
promotion requires the tokenless root-owned relay described above.

## OpenBao

OpenBao is suitable for machine identity, short leases, revocation and audit. The agent should not query secret
paths directly. A broker exchanges an OpenBao-authenticated service identity for downstream capability tokens.

## Vaultwarden

Vaultwarden remains useful for human-controlled bootstrap and recovery secrets. Do not give the autonomous VM a
universal Vaultwarden account.

## Runtime file

Create it under host tmpfs:

```bash
./scripts/create-runtime-env.sh INSTANCE
```

The script refuses to use a file not protected by mode `0600`.
