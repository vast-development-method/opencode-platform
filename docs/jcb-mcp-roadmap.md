# JCB MCP roadmap

The JCB MCP remains disabled until the internal project reaches an approved release.

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

## Integration contract

The platform expects a remote endpoint supplied as `JCB_MCP_URL` and a short-lived token supplied as
`JCB_MCP_TOKEN`. The `jcb` MCP entry remains disabled in the universal image until release approval.
