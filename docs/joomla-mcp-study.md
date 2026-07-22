# Joomla MCP integration gate

Reviewed: 2026-07-22

The platform will use only the VDM-owned Joomla MCP:

`https://github.com/vast-development-method/joomla-mcp`

The repository does not yet contain a reviewed release, so Joomla MCP is deliberately absent from the OpenCode
runtime configuration, session environment template and install process. No third-party Joomla MCP is approved as a
fallback.

## Activation gate

Add the integration only when all of the following are true:

- The repository exists and publishes a versioned release.
- The release exposes a documented capability and permission model.
- Joomla service users use ordinary ACLs and are not Super Users by default.
- Read-only and destructive tool groups are independently enforceable.
- Authentication, token rotation, audit redaction and rate limits are tested.
- Joomla 6 compatibility and upgrade behaviour are verified.
- The package reference is immutable and recorded in `manifest/sources.lock.yaml`.
- The MCP entry is added to the image only after the release review passes.

Until then, Joomla work continues through the PHP image, the Joomla CLI/API, ordinary browser testing and Git.
