# Native Joomla/JCB and Ductor integration

The platform builds reusable Incus worker images. Ductor deploys persistent
services and configures dedicated worker pools. Crabbox owns workers created for
OpenClaw; the platform's session reaper owns only its standalone OpenCode
sessions. Shared Joomla, OpenClaw and OpenBao services never run inside an
expiring worker.

## Joomla and JCB

JoomEngine's MCP image supplies Joomla, JCB and the PHP MCP package. Agents use
the authenticated Streamable HTTP endpoint at
`/api/index.php/v1/joomengine-mcp`, preserving the site's subdirectory. The
published native catalogue is authoritative. Native permissions, reviewed write
plans, confirmation, idempotency, background jobs and artifact hashes remain
owned by the server. A client-side label is not an authorization boundary.

Each site has a distinct non-secret configuration entry and a scoped Joomla
identity. Tokens are supplied through the bounded runtime credential channel;
OpenBao credentials stay on the controller. Static Joomla tokens require native
rotation or revocation even when stored in OpenBao.

Joomla must reach its own configured canonical HTTPS API URL. Worker network
permissions allow only the explicitly configured service endpoints. Neither
private service access nor gateway-to-worker SSH justifies disabling the normal
network policy.

## Company context and handoffs

Company standards are maintained in an independent Git repository. A worker
receives an immutable, revision-identified snapshot and loads its selected
instruction files at session startup. The repository remains authoritative after
the worker exits. Project artifacts are exported explicitly to durable storage
with checksums and source provenance; credentials and session authentication
state are never part of that handoff.

## Compatibility and acceptance

The image manifest records the actual installed Node runtime and immutable image
fingerprint. Ductor consumes these artifacts; it does not add another image
builder. Runtime probes verify compatibility before a worker accepts a task.

The integration acceptance path provisions the persistent service, connects a
worker, discovers permitted capabilities, performs an authorized JCB task and
retains the result. It checks permission denial, reconnect behavior, worker
expiry, service restart and operation while the deployment controller is absent.
Source tests and hosted container tests do not substitute for the actual Incus
host routing and VM lifecycle checks.
