# Native JoomEngine MCP integration

OpenCode connects directly to the PHP server in `joomengine/mcp_component` through
Streamable HTTP. This platform no longer installs the superseded
`@joomengine/joomla-mcp` TypeScript server. All agent images can use the connection;
a PHP development toolchain is not required on the agent.

The Joomla side owns tools, schemas, Joomla/JCB execution, ACL, write permissions,
plans, audit, jobs and artifacts. OpenCode owns the agent session. Ductor deploys
and configures the service infrastructure. None of these responsibilities needs a
second Joomla MCP server inside the agent VM.

## Prepare the Joomla service

Use the current JoomEngine image with the MCP package installed and enabled. The
component supports Joomla 6.1–6.x and PHP 8.3+. Enable its webservices plugin and
Joomla's API token authentication/user plugins. Configure **Canonical Joomla API
URL** with the trusted HTTPS site URL ending in `/api/index.php`.

Joomla must be able to reach its own canonical HTTPS API address. The reverse
proxy must preserve the host and authentication headers. Private certificate
authorities belong in the agent and Joomla trust stores; certificate verification
is never disabled by this integration.

Create a dedicated Joomla account/group for each automation identity. Grant
`core.login.api`, `mcp.access`, `mcp.execute`, the applicable viewing levels and
native resource permissions. For the default read-only identity, deny `mcp.write`
and do not grant `mcp.approve`, native create/edit/delete or administration access.
For intentional write access, grant only the needed native permissions and MCP
write/approval rights. A Joomla API token carries that user's authority; storing
it in OpenBao does not reduce its Joomla permissions.

## Configure one or multiple connections

```bash
./scripts/occtl.sh joomla-configure opencode-joomla \
  https://joomla.example.com/joomla/api/index.php/v1/joomengine-mcp company readonly
./scripts/occtl.sh joomla-configure opencode-joomla \
  https://builder.example.com/api/index.php/v1/joomengine-mcp builder write
```

A site base URL is also accepted and expanded to the complete endpoint. Aliases
use lowercase letters, digits, hyphens and underscores. Reconfiguring one alias preserves
other sites and unrelated OpenCode MCP entries. The command configures
`joomla_company` and `joomla_builder` with `type: remote`, `oauth: false` and an
`X-Joomla-Token` header that references an environment variable. There is no
invented OAuth flow or local HTTP listener.

`readonly` and `write` record the intended server authority. **The label is not an
authorization boundary and cannot restrict a privileged token.** The Joomla
identity and server ACL enforce access. Discovery always reflects the actual
installed server catalogue and that identity's rights.

The non-secret connection registry is `/etc/joomla-mcp/sites.json`, root-owned and
readable by the agent group. It contains endpoint, alias, token-variable name and
access intent. It contains no tokens, private keys or local approval secrets.
OpenCode configuration is read and replaced as the unprivileged agent account;
the privileged configuration command never follows paths inside the agent's home.
Existing TypeScript configuration must be reconfigured; it is not silently
interpreted as the new native-server contract.

## Credentials

The default `company` alias uses `JOOMLA_MCP_SITE_TOKEN`. Other aliases generate
`JOOMLA_MCP_<UPPERCASE_ALIAS>_TOKEN`, for example `JOOMLA_MCP_BUILDER_TOKEN`.
A fifth configuration argument can select an explicit dedicated variable using
the same naming convention. Different aliases cannot share a token reference.
Hyphens normalize to underscores in token-variable names. Consequently `a-b` and
`a_b` require distinct explicitly selected token references; collisions are rejected.

Use `occtl credentials INSTANCE` to obtain the protected runtime environment file,
or use the platform's OpenBao credential flow. Supply the token there; never pass
it as a command-line argument or commit it to OpenCode configuration. Old
`JOOMLA_MCP_APPROVAL_SECRET` and `JOOMLA_MCP_UPDATE_TOKEN` settings are not used by
the native PHP connection: the server owns consent and operation authorization.

The diagnostic helper additionally accepts a private token file through the token
variable's `_FILE` equivalent, such as `JOOMLA_MCP_SITE_TOKEN_FILE`. The file must
be owned by the current user, mode `0600`, with one hard link and no symlink. Do
not supply both a token value and a file reference. Ordinary OpenCode connections
use the session's materialized token environment, not that helper-specific option.

Restart the OpenCode session after changing connection configuration or rotating
a token. A disabled site can be left configured for later reuse:

```bash
./scripts/occtl.sh mcp opencode-joomla joomla_builder false
```

## Readiness and discovery

```bash
runtime_file="$(./scripts/occtl.sh credentials opencode-joomla)"
./scripts/occtl.sh joomla-test opencode-joomla "$runtime_file" company
```

The test performs authenticated initialization, all pages of `tools/list`,
`joomla_sites_list`, `joomla_capabilities`, and an article-list read limited to five
items. It never calls grant, planning, mutation or cancellation tools. Successful
empty article results are valid. A denied article read is reported as a failure,
not silently treated as a healthy ready connection.

Evidence stays in a private directory below
`/workspace/.artifacts/joomla-mcp/<session-id>`. It includes the actual discovered
schemas and read responses, which may contain business data. It never includes
authentication request headers. Diagnostic HTTP uses trusted HTTPS, no redirects,
30-second request limits and bounded response/pagination sizes. Tokens are passed
to curl through a private header file rather than process arguments. The helper
supports JSON and SSE-framed Streamable HTTP responses.

For direct work inside an authorized session:

```bash
vdm-joomla-mcp discover company
vdm-joomla-mcp read-test company /workspace/.artifacts/joomla-manual-read
```

The native server does not advertise tool-list-change notifications. Refresh the
MCP connection after administrator catalogue changes; do not keep a cross-user
catalogue cache. The standalone helper discovers fresh schemas for every call.

## Joomla and JCB operations

Use the installed definitions through the same connection. Start with
`joomla_actions_search` and `joomla_action_describe`; preserve objects, arrays,
GUIDs, relationship identifiers and native form semantics. The platform does not
hardcode a second JCB catalogue or invent API routes.

Writes follow the server's discovered permission request/acknowledgement,
reviewed plan and one-time apply protocol. Show the actual operation and consent
text to the operator. Do not manufacture acknowledgement or substitute a local
boolean for the server grant. Read back returned verification and retain partial
or uncertain outcomes.

For deliberate direct tool calls, store the arguments as a JSON object in a
private file and name the tool from the discovered catalogue:

```bash
umask 077
read -r -p 'Server-returned job ID: ' job_id
arguments="$(mktemp)"
jq -n --arg jobId "$job_id" '{jobId:$jobId}' > "$arguments"
vdm-joomla-mcp call builder joomla_job_status "$arguments" --confirm-call
rm -f "$arguments"
```

The file must contain the real server-returned `jobId`. `--confirm-call` means the
operator deliberately invoked this client command; it does not approve a server
permission request or write plan. This command sends exactly one tool call after
discovery and prints its native result, including a failing/uncertain result.
There is no automatic retry of mutations.

For compiler/package work, retain the returned execution/job IDs, poll
`joomla_job_status`, list `joomla_job_artifacts`, and read bounded chunks with
`joomla_job_artifact_read`. Assemble only the advertised artifact length and verify
its server-returned SHA-256. A disconnected agent can reconnect as the same
identity and inspect the job; losing a connection is not cancellation. Cancellation
can leave partial effects, and an uncertain execution needs reconciliation before
another write. See [JCB integration](jcb-mcp-roadmap.md).

## Verification

`tests/joomla-mcp-configure.sh` checks multiple aliases, preserved connections,
credential isolation and invalid endpoint rejection. `tests/joomla-mcp-http.sh`
uses a real temporary TLS server and the real curl client to check authentication,
protocol sessions, pagination, SSE, read-only test calls, job identity, no blind
write retries, redirect rejection and token-file protection. These are transport
and platform integration tests; `joomla-test` supplies evidence against the actual
deployed service.

Upstream contracts:

- https://github.com/joomengine/mcp_component/blob/main/docs/CLIENT-CONNECTIONS.md
- https://github.com/joomengine/mcp_component/blob/main/docs/GETTING-STARTED.md
- https://github.com/joomengine/mcp_component/blob/main/SECURITY.md
