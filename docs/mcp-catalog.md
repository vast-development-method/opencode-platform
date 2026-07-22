# MCP catalogue

## Enabled

### Git

Uses `mcp-server-git` from the Model Context Protocol project. It is constrained to `/workspace`.

### Playwright

Microsoft's Playwright MCP is installed in PHP, TypeScript and full images. Keep it for exploratory browser QA.
Use ordinary Playwright tests or the CLI for deterministic suites.

## Ready but disabled

### GitHub

Use the first-party `github/github-mcp-server`, preferably through GitHub's remote endpoint or a company gateway.
Enable only the toolsets needed for a task.

### Gitea

Use Gitea's own `https://gitea.com/gitea/gitea-mcp`. The company authority defaults to
`https://git.vdm.dev`. Gitea integration is a permanent platform requirement and must remain available even
while GitHub is used as the source host or CI front end.

## Internal integrations awaiting releases

### Joomla

The only approved Joomla MCP source is `https://github.com/vast-development-method/joomla-mcp`.
The generic remote configuration hook remains disabled until that repository publishes a reviewed release.
No third-party Joomla MCP is selected, documented, installed or permitted by this platform.

### JCB

JCB MCP support is deferred. The disabled generic hook remains solely to avoid an image-format migration later;
it must not be enabled until the VDM repository, protocol and first approved release exist.

## Candidate requiring approval

### Nextcloud

The current community candidate remains disabled until code, dependency and permission review is complete.

## Context control

Never enable every MCP server for every agent. Assign only the tools needed for the current task. Large tool sets
consume context and increase prompt-injection and permission risk.
