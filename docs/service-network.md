# Explicit private-service routes

Standalone OpenCode workers normally use the connected policy, which blocks
private network ranges. Do not weaken that policy for the whole fleet. Supply
an explicit per-worker route document to `occtl network-configure INSTANCE FILE`:

```json
{
  "schema": 1,
  "dns": ["10.248.18.1"],
  "services": [
    {"name": "joomla-mcp", "address": "10.50.0.12", "port": 443},
    {"name": "model-gateway", "address": "10.50.0.13", "port": 443}
  ],
  "ssh_sources": ["10.50.0.10"]
}
```

These are example addresses; select the actual service, DNS and optional SSH
source addresses from your infrastructure. The renderer accepts exact IPv4
addresses and TCP ports, never CIDRs, hostnames, wildcard routes, metadata,
loopback or shared address space. Ingress allows SSH only from listed sources;
omit `ssh_sources` when inbound SSH is unnecessary. DNS allows TCP/UDP 53 only
to selected resolvers. All other new connections are rejected. Responses are
handled by Incus's native connection tracking.

The command creates an ownership-marked ACL and overrides only this worker's
NIC ACL. It refuses non-platform workers and Ductor/Crabbox ownership markers.
It does not modify shared network profiles, add public ingress, or alter host
firewalls. Reapply a reviewed document to change routes. Service address changes
require an explicit update; DNS resolution alone cannot silently broaden an IP
allowlist. Existing established connections may require worker restart when
revoking access because firewall connection tracking can retain them.

Use Ductor's explicit network/profile configuration for Ductor-owned pools.
Those pools must allow the selected gateway-to-worker SSH and worker-to-service
paths while keeping Incus administration inaccessible from the guest. OpenBao
credential retrieval occurs on the controller, so it does not require worker
access to OpenBao.

Your external proxy supplies the domain and TLS. Preserve the canonical Host
and authorization headers and permit Joomla to reach its own canonical API URL.
Verify the TLS name from both the worker and Joomla service VM. A container
healthcheck alone cannot prove this routing contract.
