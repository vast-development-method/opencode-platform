# Roadmap and release-candidate gates

## RC definition — implemented in source

- Manifest schema 2 is the single authority for images, languages,
  capabilities, policies, sizes, architectures, profiles and CI matrices.
- Six composable release images remain: base, PHP, Python, C/C++, TypeScript
  and full. Android, GPU, GUI, containers, audio and security tooling are
  catalogued as planned and cannot enter a release matrix accidentally.
- Incus restricted projects, fail-closed policy profiles, public-only connected
  egress and session TTL enforcement are defined.
- Architecture-specific package identities, SBOM/Grype hooks, provenance,
  OpenBao-backed Cosign hooks, tamper verification and upload-last Gitea
  completion markers are defined.
- GPL-3.0-only licensing and Vast Development Method ownership are established.

## RC evidence — next mandatory milestone

The platform must not be promoted from RC until all gates pass:

1. Bootstrap a clean Ubuntu host including QEMU/KVM and Incus.
2. Build all six amd64 images from the exact protected commit/tag.
3. Run language, browser, sanitisation and negative network tests.
4. Generate SBOMs, pass the vulnerability policy and sign every package.
5. Export every image and verify its signed package.
6. Import, boot and smoke-test every package on a second clean amd64 host.
7. Verify connected, offline and gateway policies against host, RFC1918,
   metadata and public targets.
8. Verify cgroup TTL termination after caller loss and host reaper cleanup.
9. Exercise provider, GitHub App, Gitea MCP and short-lived SSH certificate
   paths through the broker.
10. Publish the signed completion index only after all evidence is present.

ARM64 stays declared but non-promotable until equivalent native ARM64 evidence
exists.

## Broker and tokenless relay

- Deploy OpenBao with audit, backup/restore, workload authentication and
  carefully scoped policies.
- Deploy LiteLLM and MCP authorization gateways.
- Replace transitional session environment credentials with the root-owned
  tokenless guest relay.
- Configure self-hosted Squid allowlists for restricted and release policies.
- Prove revocation, model budgets, repository/tool restrictions and bastion-only
  VPS access.

## Fleet self-service

- Separate developer, builder and disposable automation Incus projects.
- Add OIDC and self-hosted OpenFGA; ordinary users must never join
  `incus-admin`.
- Add a narrow provisioning API, task queue, quotas, ownership records, audit
  events, health reconciliation, warm pools and automatic retirement.
- Promote images through signed candidate/stable channels.

## VDM Joomla and JCB

- Release and review `vast-development-method/joomla-mcp`.
- Complete the JCB MCP protocol and test suite.
- Add each integration only after its own activation and credential-scope gate.
