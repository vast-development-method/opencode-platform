# Roadmap

## Phase 1: Baseline — implemented

- Validate the repository on GitHub-hosted and Gitea runners.
- Build all six variants on a trusted Incus runner.
- Pilot local Git and Playwright MCP.
- Configure ChatGPT Plus, Anthropic API, xAI API and local Llama routes.
- Expose short-lived GitHub build artifacts and publish durable image packages to Gitea.

## Phase 2: Broker

- Deploy OpenBao and LLM gateway.
- Implement short-lived virtual keys and budgets.
- Put Gitea, GitHub and Nextcloud MCP behind the gateway.
- Enforce DNS-aware egress policy.
- Add central audit and revocation tests.

## Phase 3: VDM Joomla and JCB

- Release and review `vast-development-method/joomla-mcp`.
- Complete JCB MCP protocol and test suite.
- Add each integration only after its own activation gate passes.

## Phase 4: Fleet

- Central Incus cluster.
- Department profiles and quotas.
- Image promotion channels.
- Automated retirement and compliance reporting.
- Disposable task VMs and pull-request-only automation.
