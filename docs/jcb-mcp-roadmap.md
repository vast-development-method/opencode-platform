# JCB through the native Joomla MCP connection

JCB is a supported integration through the existing PHP JoomEngine MCP server.
It does not need a separate JCB MCP service, npm adapter or second API catalogue
inside opencode-platform. Agents use the same configured Joomla MCP endpoint and
a dedicated Joomla identity whose permissions match their work.

## Deployment and synchronization

Use the JoomEngine service image containing JCB and the MCP package. Enable JCB's
native registration plugins. After updating a component or its route/command
plugin, refresh the stored catalogue in **JoomEngine MCP → Operations → Refresh
JCB definitions**, or run the existing local administrator command:

```bash
php cli/joomla.php joomla:mcp:jcb-sync
```

Synchronization discovers the actual installed component APIs and command input
contracts, retaining administrator customization. Ordinary agent discovery reads
the catalogue and does not perform synchronization. Routes depend on installed
registration plugins; disabling a plugin removes its operations from discovery
and execution.

## Agent workflow

1. Discover the authenticated tools and capabilities, then search and describe the
   relevant installed JCB actions. Use their actual schemas, including GUID and
   unique-key routes, nested filters, form/subform inputs and relationship IDs.
2. Read definitions and related records through those actions. Treat source-code
   fields as definition data and keep the Joomla identity's resource ACL intact.
3. Prepare changes using the native permission/grant/plan/apply flow. Review the
   effective options, repository identity, definition changes and side effects.
4. Submit compilation and package operations through the existing job tools.
   Package `get`, `init`, `pull`, `push` and `reset` are effectful operations even
   where their names sound like reads. The server remains the execution authority.
5. Retain the returned job/execution identity. Poll status, download the advertised
   artifacts in bounded chunks and verify their lengths and SHA-256 values before
   placing compiled output in the repository review workflow.
6. Review generated changes with a separate agent identity/session where desired.
   Reconnect to inspect retained jobs after interruption; do not blindly replay a
   mutation or treat cancellation as rollback.

The API user must have the native JCB permissions required by the operation plus
its MCP permissions. Server-side workers keep the requesting user's authority;
they do not turn a remote agent into the trusted local CLI owner. Workers need a
compatible PHP CLI, `pcntl_fork`, `posix_setsid`, `proc_open` and private writable
artifact storage.

## Operational boundaries

Compilation and package commands use the server's reviewed native job adapter.
Entity CRUD uses installed API contracts. These are complementary supported
surfaces. Unsupported custom API contracts or native Joomla/JCB errors must remain
visible; the agent must not substitute direct SQL, unrestricted shell access or a
fabricated successful result.

The platform provides connection configuration, scoped runtime credentials,
protocol diagnostics and agent sessions. Joomla MCP provides grants, plans,
idempotency, job state, artifacts and audit. Ductor provides infrastructure service
deployment. Keeping those responsibilities in their existing owners avoids lock-in
and duplicate execution engines.

See [native Joomla MCP setup](joomla-mcp-study.md) and the upstream
[JCB contract](https://github.com/joomengine/mcp_component/blob/main/docs/integrations/JCB.md).
