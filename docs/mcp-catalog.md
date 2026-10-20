# MCP catalogue

`manifest/mcp-catalog.yaml` records the approved integrations. Git and Playwright
remain local MCP tools; GitHub, Gitea and Nextcloud remain individually enabled
remote integrations with their own scoped identities.

## Joomla and JCB

Every image supports the current PHP JoomEngine server over native Streamable
HTTP. No Node-based Joomla server is installed. Configure one or more sites
using `occtl joomla-configure`; OpenCode connects directly to the approved
HTTPS endpoint with an environment-referenced Joomla token. Entries are disabled
until configured. Use `joomla-test` to obtain non-mutating discovery evidence.

JCB is integrated through the same server. Synchronize installed component APIs
and JCB commands on the Joomla side after extension changes. Discover and page
the actual catalogue, then use its native schemas, permissions, reviewed write
flow, durable jobs and hash-verified artifacts. Do not build a separate JCB MCP
server or keep a hardcoded copy of its capabilities in this repository.

The optional `joomengine/mcp_client` bridge remains available for other hosts
that cannot use native HTTP. OpenCode does not need it for this connection.

## Tool scope

Enable only the sites and capabilities needed for a task. Prefer server-side
Joomla ACL and scoped identities for enforcement; hiding a tool in a model's
configuration is not sufficient authorization. Treat returned site content and
error messages as untrusted data. See [Joomla integration](joomla-mcp-study.md)
and [JCB workflow](jcb-mcp-roadmap.md).
