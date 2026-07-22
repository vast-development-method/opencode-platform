# Known limitations

- Static and mocked validation is available, but the six real Incus images have
  not yet been built in this delivery environment.
- Ubuntu and Node packages still resolve from upstream repositories. The
  NodeSource setup input is content-pinned, and release manifests record the
  result, but a timestamped Ubuntu/package snapshot has not yet been enabled.
- Syft, Grype and Cosign hooks fail closed in release mode, but a trusted
  builder still needs those pinned tools and a short-lived OpenBao signing
  identity.
- AMD64 is the only promotable architecture. ARM64 identities are collision-safe
  but remain disabled until native ARM64 build/import evidence exists.
- Connected policy denies private, metadata and management IPv4 ranges while
  retaining public Internet. Host-side DNS-aware Squid policy is still required
  before brokered, restricted and release policies can be unblocked.
- Session secrets no longer appear in Incus command arguments and the process
  tree has a systemd-enforced TTL. The transitional session process still
  exports scoped credentials to OpenCode and its children; the tokenless
  root-owned relay remains a release gate.
- OpenBao/LiteLLM policies and routes are defined but the external broker,
  authorization gateway, audit device, unseal, backup and revocation tests are
  not deployed by this repository.
- GitHub/Gitea builds require owned hardware-virtualisation runners. A second
  independent clean host is mandatory for redistribution evidence.
- OpenCode configuration compatibility must be revalidated whenever OpenCode is
  upgraded.
