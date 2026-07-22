# Joomla MCP study

Reviewed: 2026-07-17

This repository does not automatically install a Joomla MCP until the company selects and audits an implementation.

## Candidate A: MCP4Joomla

Repository: `nikosdion/joomla-mcp-php`

Strengths:

- PHP implementation for Joomla 5.2 and later, including Joomla 6.
- Very broad coverage: the current README reports 249 tools across 22 categories.
- Category and exact-tool filters.
- `--non-destructive` read-only mode.
- Extra forbidden-value protection.
- PHAR and source deployment.
- Extension point for custom tools.

Risks and questions:

- It expects a Joomla API token for a Super User in its basic configuration.
- A very large tool catalogue can overwhelm model context and broadens the permission surface.
- It is a local stdio process holding a powerful token.
- Company policy should require narrowly scoped Joomla users and explicit category selection.

## Candidate B: Joomla MCP component

Repository: `OnepointConsultingLtd/joomla-mcp-server`

Strengths:

- Joomla 4, 5 and 6 component exposing HTTP JSON-RPC.
- Current README reports 66 tools.
- Bearer authentication, IP allow-listing, CORS controls, rate limiting, caching and health endpoint.
- Read-only mode and disabled-tool list.
- High-risk extension install/uninstall and template editing tools disabled by default.
- Deliberately excludes user management and global configuration.

Risks and questions:

- A component installed in the Joomla site increases the site's own attack surface.
- Some operations use database or filesystem APIs when Web Services are insufficient.
- Remote endpoint lifecycle, upgrade and vulnerability response must be owned.
- The internal API token and external bearer token both require rotation procedures.

## Provisional direction

Use the component model as the preferred remote architecture for company operation because it keeps site-specific
logic beside Joomla and supports network controls. Use MCP4Joomla as an important reference for broad Joomla API
coverage, filtering and extensibility.

A VDM-owned Joomla MCP should combine:

- remote streamable HTTP;
- ordinary Joomla ACL enforcement;
- dedicated service users rather than Super User by default;
- per-tool and per-category policy;
- read-only default;
- dangerous-tool compile-time or administrator gating;
- audit records with parameter redaction;
- pagination and response-size limits;
- idempotency and dry-run support;
- health, version and capability discovery;
- test fixtures for Joomla 4/5/6 as required;
- extension hooks for JCB without coupling core Joomla tools to JCB.

## Approval checklist

- Threat model complete.
- Tool inventory reviewed.
- No token returned in logs or errors.
- Read-only role tested.
- Destructive tools require explicit policy.
- Prompt-injection tests complete.
- Rate and response limits tested.
- Release artefacts signed and reproducible.
- Upgrade and rollback documented.
