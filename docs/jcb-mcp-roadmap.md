# JCB MCP roadmap

The JCB MCP is not installed or represented by a runtime endpoint. It will be added only after the internal
repository exists and publishes an approved release.

## Required capability groups

- Read component-builder metadata and GUID relationships.
- Inspect component, plugin, module and package definitions.
- Validate generated architecture without publishing.
- Compile into an isolated output directory.
- Compare generated artefacts.
- Run JCB-specific static validation.
- Create migration plans.
- Export/import approved repository representations.
- Open issues or pull requests through Gitea, not by direct production mutation.

## Security defaults

- Read-only by default.
- No database credentials exposed to the client.
- No direct production compilation.
- No arbitrary PHP execution.
- No unrestricted file path parameters.
- No release, tag, merge or deployment without explicit approval.
- Every mutation produces an auditable change set.
- Per-project and per-component scope.

## Integration gate

The future release must define its transport, endpoint, short-lived authentication, capability catalogue and
permission model. Only then should a pinned source entry, runtime variables and a disabled-by-default OpenCode MCP
entry be introduced in one reviewed change.
