# Gitea packages and images

## Authority split

- Git repository: source of truth.
- Generic Package Registry: exported Incus image files, checksums and manifests.
- Container Registry: broker and MCP OCI images.
- Native Incus remote: optional fast cache for direct launches.

## Publish

```bash
./scripts/package-image.sh php

export GITEA_PACKAGE_OWNER=platform
export GITEA_PACKAGE_USER=package-publisher
export GITEA_PACKAGE_TOKEN='runtime-only-token'
./scripts/publish-gitea-package.sh php
```

The publisher token needs package write permission only. Colleagues should receive read-only package access.

## Import

Download every file in the package version, verify `SHA256SUMS`, then:

```bash
incus image import ./vdm-opencode-php-0.1.0* --alias vdm-opencode-php/0.1.0
```

Do not commit exported VM files into Git history.
