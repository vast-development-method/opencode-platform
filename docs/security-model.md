# Security model

## Assumptions

Repository content, generated code, package scripts, websites, MCP output and LLM output may be hostile.

An Incus VM protects the host better than a normal process or container, but it does not make credentials invisible
to code running inside the VM.

## Non-negotiable controls

- No host home or source mounts.
- No host Docker socket.
- No YubiKey, SSH agent or GPG agent forwarding.
- No long-lived provider, Gitea, GitHub, Nextcloud or Joomla credentials in images.
- No direct push to protected branches.
- No shared VM user account between colleagues.
- OpenCode sharing disabled.
- External-directory access denied by managed configuration.
- Runtime authentication data placed under guest `/run`.
- Company remote MCP servers disabled until explicitly enabled.
- Browser tests barred from destructive production actions.

## Network policy

Incus ACLs provide a baseline but are not DNS-aware enough for a complete corporate allow-list. Use a trusted
outbound proxy or firewall that allows only:

- the LLM gateway;
- approved MCP gateways;
- Gitea/GitHub as required;
- Nextcloud as required;
- package mirrors during controlled maintenance;
- DNS and time infrastructure.

Do not permit agent VMs to reach management VLANs, hypervisor APIs, Vaultwarden, OpenBao administration, databases,
backup servers or production SSH directly.

## Snapshots

Only stateless stopped snapshots may become shared images. Never publish a stateful snapshot because guest memory
may contain session tokens.

## Build hygiene

The finaliser removes OpenCode auth files, MCP auth files, shell history, SSH private keys and token-like files.
The verification test blocks publication if these remain. This is defence in depth, not proof that arbitrary
secret text never appeared elsewhere; build from a clean base and do not authenticate during image construction.
