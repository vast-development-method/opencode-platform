# Changelog

## Unreleased

- Made VM launch metadata atomic, safe when `USER` is absent, and self-cleaning
  when a newly created instance cannot start.
- Replaced the checkout-based root timer target with a root-owned installed
  runtime and tightened the systemd service sandbox.
- Replaced implicit Incus sudo fallback with explicit privilege selection and
  bootstrap-managed `incus-admin` onboarding.
- Made Gitea publication retries validate an existing semantic completion
  marker and derive release time from the immutable package manifest.
- Fixed guest runtime cleanup, minimal-host VM listing, configurable agent
  home/user support, and browser-MCP image invariants.
- Added executing runtime and publication regressions, semantic authority
  validation, and a local `make ci` target.

## 0.3.0-rc.3 - 2026-07-29

- Separated adaptive image-build resources from launch-time runtime sizes,
  reserving host memory/CPU and failing before Incus changes when current
  capacity is insufficient.
- Added resumable stopped build checkpoints, non-secret failure diagnostics and
  a detached managed cache for APT, npm, pip and Playwright downloads.
- Removed unnecessary build and first-launch snapshots; verified images now
  publish directly from stopped instances.
- Moved bridge/ACL ownership to the Incus default project, added collision and
  legacy-migration guards, made ACL state explicit and retained restricted
  project isolation.
- Hardened host bootstrap around dpkg/APT health, active Incus upgrades and
  latest configured package candidates without changing repositories,
  coreutils providers, Docker or firewall policy.
- Fixed TSX version normalisation, replaced an undeclared Python `uv`
  dependency with the installed `pipx`, and corrected the Joomla live-test
  executable typo with an executed guest-dispatch regression test.
- Added complete host, hardware, caching, recovery and network documentation.

## 0.3.0-rc.2 - 2026-07-27

- Added `joomla-mcp` as a manifest-owned composable capability for PHP and full images.
- Pinned and verified `@joomengine/joomla-mcp@0.7.0` from the public JoomEngine repository.
- Added stable stdio, HTTP, live-test and configuration-check wrappers while keeping Joomla disabled and
  unconfigured in every published image.
- Added HTTPS-only single-site profile generation with read-only defaults, bounded write profiles, separate update
  credentials and indefinite grants disabled.
- Extended the systemd credential path with Joomla site, approval and update values, duplicate-key rejection and
  required-credential preflight.
- Added a non-mutating in-image read test that retains redacted evidence under the workspace without placing
  credential values in Incus arguments.
- Added build verification, manifest/source-lock tests, stale-repository detection and complete operator
  documentation for deployment, use, testing, network boundaries and promotion.

## 0.3.0-rc.1 - 2026-07-22

- Made `manifest/images.yaml` the schema-validated authority for composition,
  architectures, policies, sizes, profiles and GitHub/Gitea matrices.
- Added GPL-3.0-only licensing and Vast Development Method copyright ownership.
- Added restricted Incus projects, public-only connected egress, offline and
  fail-closed gateway policies, enforced session TTLs and VM expiry reaping.
- Removed Java and split browser/database provisioning into reusable components.
- Added architecture-safe artifacts, provenance, SBOM/Grype release gates,
  OpenBao-backed Cosign hooks and upload-last Gitea completion markers.
- Added OpenAI, Claude, Gemini, Grok and local gateway routes plus Git/VPS
  capability-path documentation.
- Added static manifest, security, drift, matrix and artifact tamper tests.

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
