# Versioning and promotion

The repository version, image alias, Gitea package version and release tag must match.

```text
Repository tag:       v0.3.0-rc.1
Incus alias:          vdm-opencode-php/0.3.0-rc.1-amd64
Gitea package:        vdm-opencode-php-amd64/0.3.0-rc.1
Build manifest:       /etc/vdm-opencode-platform/build.json
```

## Release channel

Before a release:

1. Review and deliberately update `manifest/toolchain.env` and `manifest/sources.lock.yaml`.
2. Confirm that no floating dependency or mutable GitHub Action reference was introduced.
3. Build from a clean, trusted Incus runner.
4. Run repository, guest, browser and security tests.
5. Export the image and verify the generated manifest and `SHA256SUMS`.
6. Pilot the image.
7. Tag the repository with the exact value from `VERSION` prefixed by `v`.
8. Retain the GitHub workflow artifact as a short-lived download and publish the durable package to Gitea.

Do not mutate an existing released image alias. Publish a new semantic version.
