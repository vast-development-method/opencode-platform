# VDM Joomla MCP integration

The only approved Joomla MCP implementation for this platform is:

- Repository: `https://github.com/vast-development-method/joomla-mcp`
- Owner: Vast Development Method
- Status: not yet released
- Platform state: disabled

No third-party Joomla MCP implementation is selected, installed, referenced as a candidate or permitted as a
fallback.

## Activation gate

The existing remote `joomla` configuration entry is an inert compatibility hook. Do not enable it until the VDM
repository exists and supplies all of the following:

1. A tagged release and immutable source reference.
2. Documented transport, authentication and Joomla compatibility.
3. A reviewed tool inventory and Joomla ACL mapping.
4. Read-only defaults and explicit destructive-operation policy.
5. Audit logging with credential and sensitive-parameter redaction.
6. Pagination, response-size and rate limits.
7. Automated tests for the supported Joomla 6.x versions.
8. Signed or checksummed release artifacts.
9. Upgrade, rollback and incident-response procedures.

When those gates pass, pin the exact release in `manifest/sources.lock.yaml`, set the runtime
`JOOMLA_MCP_URL` and short-lived `JOOMLA_MCP_TOKEN`, then enable the server only for agents that need it.
