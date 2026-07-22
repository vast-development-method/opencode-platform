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

Tagged GitHub builds can publish the same package set to Gitea when repository variable
`GITEA_PUBLISH_ENABLED=true`, variable `GITEA_BASE_URL`, owner/user variables and secret
`GITEA_PACKAGE_TOKEN` are configured. Gitea tag builds publish directly through `.gitea/workflows/build-images.yaml`.

## Import

Download every file in one package version, then use the checked import helper:

```bash
./scripts/import-image-package.sh ./downloaded-package
```

The helper verifies every checksum and the manifest before importing the Incus payload. It refuses to overwrite an
existing image alias.

Do not commit exported VM files into Git history.
