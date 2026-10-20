# Scoped runtime credentials

The controller retains infrastructure credentials. A worker receives only the
values selected for its task through systemd `LoadCredential`, under a bounded
service and tmpfs data directory. The host file is caller-owned mode 0600, cannot
be a symlink or hard link, and contains only allowlisted single-line values.
Neither values nor the OpenBao controller token enter Incus command arguments.

## Native Joomla/JCB

Use a dedicated Joomla API identity per site and scope. The default site uses
`JOOMLA_MCP_SITE_TOKEN`; additional aliases use `JOOMLA_MCP_<ALIAS>_TOKEN`.
OpenCode's non-secret configuration contains an environment reference, endpoint
and `oauth: false`. Joomla's native token and ACL authorize requests. A client
label such as `readonly` is not an authorization check.

The PHP server owns grants, reviewed plans, explicit confirmation, idempotency,
audit, native target permissions, jobs and artifacts. The old TypeScript adapter's
approval secret and separate client catalogue are not used. Remove obsolete
`JOOMLA_MCP_APPROVAL_SECRET`, `JOOMLA_MCP_UPDATE_TOKEN`, `JCB_MCP_URL` and
`JCB_MCP_TOKEN` entries when migrating an old runtime file. Rebuild older images
before configuring the native connection.

`occtl joomla-import INSTANCE DUCTOR_CLIENT_JSON` accepts Ductor's protected
client document, configures its endpoint and alias, and atomically copies its
scoped token into the host's tmpfs runtime file. No token is displayed.

## OpenBao KV-v2 retrieval

`occtl credentials-fetch INSTANCE CONFIG_JSON` reads exact permitted KV-v2
fields over verified HTTPS and atomically updates the runtime file. Keep this
configuration outside the image and repository, owned by the caller with mode
0600. For example, using your deployed address and secret locations:

```json
{
  "schema": 1,
  "address": "https://bao.example.com:8200",
  "token_file": "/run/user/1000/bao-session-token",
  "secrets": [
    {"key": "JOOMLA_MCP_SITE_TOKEN", "mount": "kv", "path": "joomla/company", "field": "token"}
  ]
}
```

An optional `ca_file` names a private CA certificate. The controller token file
must be caller-owned, mode 0600, single-link and on tmpfs. Obtain that token
through your existing OpenBao workload authentication; its policy needs only
`read` on the exact `kv/data/joomla/company` path. Do not use a root token or give
the worker an OpenBao identity that can enumerate all company secrets.

```bash
runtime_file="$(./scripts/occtl.sh credentials-fetch opencode-joomla /secure/company-bao.json)"
./scripts/occtl.sh session opencode-joomla "$runtime_file"
```

The helper neither follows redirects nor disables TLS verification. Partial
retrieval, a missing field or malformed values leave the prior credential file
unchanged. Rotations are fetched explicitly before a new session. Long-lived
Joomla tokens still need native rotation/revocation; OpenBao storage alone does
not grant expiry to a downstream token. Stopping Ductor does not revoke running
service credentials or stop Joomla.

## Boundaries

Processes can inspect credentials they legitimately use. Limit the identity's
server-side permissions and exposure window. Never export runtime directories,
OpenCode authentication state or provider secrets as review handoffs.

The older `broker/` Compose stack remains optional reference infrastructure for
LLM routing. Native Joomla MCP connectivity and KV retrieval do not depend on
that stack, an invented OAuth exchange or an unfinished tokenless relay. Reuse
Ductor's deployed OpenBao service rather than creating another one implicitly.
