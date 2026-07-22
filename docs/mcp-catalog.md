# MCP catalogue

## Enabled

### Git

Uses `mcp-server-git` from the Model Context Protocol project. It can inspect and modify repositories and is still
described upstream as early development. Version `2026.7.10` is preinstalled and constrained to `/workspace`.

### Playwright

Microsoft's Playwright MCP is installed in PHP, TypeScript and full images. Keep it for exploratory, persistent
browser QA. The package is pinned and runs with an isolated browser profile. For large deterministic suites,
ordinary Playwright tests or the Playwright CLI are more token-efficient.

## Ready but disabled

### GitHub

Use the first-party `github/github-mcp-server`, preferably through GitHub's remote endpoint or a company gateway.
Limit toolsets; the full server can add substantial context and permissions.

### Gitea

Use Gitea's own `https://gitea.com/gitea/gitea-mcp`. The company authority defaults to `https://git.vdm.dev`.
The platform keeps its runtime endpoint and short-lived token support. Expose the audited deployment through the
company MCP gateway.

## Candidate requiring approval

### Nextcloud

`cbcoutinho/nextcloud-mcp-server` is the current leading candidate because it exposes broad Files, Calendar,
Contacts, Deck, Notes, Tables, Talk and other coverage, supports streamable HTTP and Login Flow v2, and provides
tag-based exclusion. It remains community software and needs code, dependency and permission review.

## Deferred VDM integrations

### Joomla MCP

No Joomla MCP is installed or configured in the images. The only approved future source is
`https://github.com/vast-development-method/joomla-mcp`. See `docs/joomla-mcp-study.md`.

### JCB MCP

No JCB MCP is installed or configured. Integration starts only after the internal repository and its first reviewed
release are available. See `docs/jcb-mcp-roadmap.md`.

## Context control

Never enable every MCP server for every agent. Assign only the tools needed for the current task. Large tool sets
consume context and increase prompt-injection and permission risk.
