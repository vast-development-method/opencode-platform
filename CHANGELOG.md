# Changelog

## 0.2.0 - 2026-07-22

- Split GitHub and Gitea workflows so each uses its own expression context and runner model.
- Moved repository validation to a GitHub-hosted runner and added Incus build-runner preflight checks.
- Added downloadable GitHub workflow artifacts while preserving Gitea Generic Package publication.
- Pinned OpenCode, Git MCP, Playwright, TypeScript, Ruff, mypy and GitHub Action versions.
- Preinstalled Git MCP instead of downloading it dynamically at runtime.
- Added checksummed package manifests and a safe Incus package import helper.
- Removed all third-party Joomla MCP references and all premature Joomla/JCB runtime entries.
- Reserved only the VDM-owned Joomla MCP repository as a deferred integration.

## 0.1.0 - 2026-07-17

- Initial company platform definition.
- Added Incus project, networks, ACL and six VM profiles.
- Added repeatable image builders and Gitea package publishing.
- Added common OpenCode agent framework.
- Added Git and Playwright MCP integration.
- Added gated GitHub, Gitea, Nextcloud and speech MCP definitions.
- Added broker scaffold, runtime-only credential flow, browser QA and voice transcription.
