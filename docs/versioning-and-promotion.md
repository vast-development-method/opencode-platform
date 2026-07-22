# Versioning and promotion

The repository version, image alias, Gitea package version and release tag must match.

```text
Repository tag:       v0.1.0
Incus alias:          vdm-opencode-php/0.1.0
Gitea package:        vdm-opencode-php/0.1.0
Build manifest:       /etc/vdm-opencode-platform/build.json
```

## Development channel

Floating upstream references may be used only while the platform is being explored. The resulting image must not
be promoted to company production.

## Release channel

Before a release:

1. Replace `REVIEW_AND_PIN` entries in `manifest/sources.lock.yaml`.
2. Replace `@latest` package references with exact approved versions.
3. Mirror or archive upstream artefacts where licensing permits.
4. Record SHA-256 checksums.
5. Build from a clean runner.
6. Run repository, guest, browser and security tests.
7. Export and checksum the image.
8. Pilot the image.
9. Tag the repository and publish the matching package version.

Do not mutate an existing released image alias. Publish a new semantic version.
