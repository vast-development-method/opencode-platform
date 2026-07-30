# Known limitations

- Static validation plus executing mocked launch, cleanup, listing, reaper,
  credential and publication-retry tests are available, but the six real Incus
  images have not yet been built in this delivery environment.
- Build-resource selection, resumable checkpoints and cache detachment are
  covered by repository tests, but release promotion still requires a real
  clean `--no-cache` build on two independent hardware-virtualisation hosts.
- JoomEngine MCP for Joomla `0.7.0` is now pinned, installed and fail-closed in
  PHP/full images, but upstream still retains live-production evidence gates for
  action families. This repository's safe helper proves only the configured
  read profile; mutation/admin certification requires disposable-site evidence
  and review of the upstream coverage/recovery status.
- Ubuntu and Node packages still resolve from upstream repositories. The
  NodeSource setup input is content-pinned, exact npm package versions are
  verified, and release manifests record the result, but a timestamped
  Ubuntu/npm package snapshot has not yet been enabled.
- Syft, Grype and Cosign hooks fail closed in release mode, but a trusted
  builder still needs those pinned tools and a short-lived OpenBao signing
  identity.
- AMD64 is the only promotable architecture. ARM64 identities are collision-safe
  but remain disabled until native ARM64 build/import evidence exists.
- Connected policy denies private, metadata and management IPv4 ranges while
  retaining public Internet. A public HTTPS Joomla site is reachable; a private
  Joomla site requires the still-gated brokered/restricted path or an explicit
  lab policy.
- Session secrets no longer appear in Incus command arguments, required Joomla
  credential names are preflighted, and the process tree has a
  systemd-enforced TTL. The session process and its authorised children can
  still inspect credentials they must use; the tokenless root-owned relay
  remains a broader release gate.
- OpenBao/LiteLLM policies and routes are defined but the external broker,
  authorization gateway, audit device, unseal, backup and revocation tests are
  not deployed by this repository.
- GitHub/Gitea builds require owned hardware-virtualisation runners. A second
  independent clean host is mandatory for redistribution evidence.
- OpenCode configuration compatibility must be revalidated whenever OpenCode is
  upgraded.
- Ubuntu 24.04/26.04 host portability is covered by fail-closed package,
  privilege, systemd-unit and command-path contracts, and repository CI runs on
  both GitHub-hosted OS images. Real KVM acceptance on both releases remains a
  promotion gate; hosted CI cannot prove kernel virtualization, bridge egress
  enforcement or a live systemd timer.
