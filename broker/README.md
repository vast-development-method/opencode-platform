# External credential and capability broker

This directory describes a broker host outside all agent VMs.

It separates:

- long-lived provider credentials;
- short-lived agent session identities;
- LLM routing and budgets;
- MCP service credentials;
- TLS termination and audit boundaries.

The Compose file is intentionally blocked until immutable image references are supplied. Do not set `latest`.

## Production requirements

Before deployment:

1. Pin image digests and verify provenance.
2. Put OpenBao behind TLS; the included plain HTTP listener is only for the private Compose network.
3. Use a supported OpenBao auto-unseal or carefully operated manual unseal process.
4. Store provider keys through an approved secret injection mechanism, not a committed `.env`.
5. Configure LiteLLM virtual keys, budgets, rate limits and per-team model allow-lists.
6. Put every remote MCP server behind authenticated TLS.
7. Log metadata without logging prompts, source code or credentials unless policy explicitly permits it.
8. Test immediate token revocation.
9. Back up broker state independently of Incus images.

The initial platform can operate without this stack by using runtime-only session values. The broker is the path to
centralised corporate operation, not a requirement for first image builds.
