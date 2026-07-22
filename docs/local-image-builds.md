# Local image builds and releases

This path builds, packages, verifies and optionally publishes Incus images entirely on an in-house builder. GitHub does not need network access to the builder. The host only needs outbound access to clone the repository, obtain build dependencies and, when enabled, upload packages to Gitea.

## One-time builder setup

Use a trusted Ubuntu host with hardware virtualisation, read/write access to `/dev/kvm`, Incus, and at least the configured `MIN_BUILD_FREE_GIB`.

```bash
git clone https://github.com/vast-development-method/opencode-platform.git
cd opencode-platform
cp .env.example .env
./scripts/bootstrap-host.sh
./scripts/ci/check-incus-runner.sh
```

The builder does not need a GitHub Actions runner or a Gitea Actions runner.

## Build locally without publishing

Build all six variants:

```bash
export LOCAL_BUILD_VARIANTS=all
./scripts/local-image-release.sh
```

Build only the most useful initial variants:

```bash
export LOCAL_BUILD_VARIANTS='php,typescript,full'
./scripts/local-image-release.sh
```

Packages remain under `build/packages/<version>/<architecture>/<variant>/`.
Every package contains the Incus export, manifest, provenance and checksums;
release mode additionally requires an SBOM, vulnerability scan and signature.

## Publish directly to Gitea

Create a dedicated Gitea package publisher account and a package-write-only token. Keep the token out of `.env`, shell history, Git, and the built images.

```bash
read -rsp 'Gitea package token: ' GITEA_PACKAGE_TOKEN
printf '\n'
export GITEA_PACKAGE_TOKEN

export LOCAL_BUILD_VARIANTS=all
export LOCAL_PUBLISH_GITEA=true
export GITEA_BASE_URL='https://git.vdm.dev'
export GITEA_PACKAGE_OWNER='vast-development-method'
export GITEA_PACKAGE_USER='package-publisher'

./scripts/local-image-release.sh
unset GITEA_PACKAGE_TOKEN
```

The package names are `vdm-opencode-<variant>`, and the package version is read from both `VERSION` and `manifest/platform.env`. The command refuses to run if those versions disagree.

## Production tagged release

For a reproducible production release, build the exact protected tag and require both a clean checkout and the matching tag:

```bash
git fetch --tags --prune origin
git switch --detach v0.3.0-rc.1

export LOCAL_BUILD_VARIANTS=all
export LOCAL_REQUIRE_CLEAN=true
export LOCAL_REQUIRE_TAG=true
export LOCAL_PUBLISH_GITEA=true
export GITEA_BASE_URL='https://git.vdm.dev'
export GITEA_PACKAGE_OWNER='vast-development-method'
export GITEA_PACKAGE_USER='package-publisher'

read -rsp 'Gitea package token: ' GITEA_PACKAGE_TOKEN
printf '\n'
export GITEA_PACKAGE_TOKEN

./scripts/local-image-release.sh
unset GITEA_PACKAGE_TOKEN
```

Replace `v0.3.0-rc.1` with the version being released. Tags must not be recreated or force-moved after packages are published.

## Supported environment variables

| Variable | Default | Purpose |
|---|---:|---|
| `LOCAL_BUILD_VARIANTS` | `all` | Comma- or space-separated variants, or `all`. |
| `LOCAL_PUBLISH_GITEA` | `false` | Upload verified packages directly to Gitea. |
| `LOCAL_REQUIRE_CLEAN` | `true` | Refuse a dirty Git checkout. |
| `LOCAL_REQUIRE_TAG` | `false` | Require HEAD to have tag `v<VERSION>`. |
| `GITEA_BASE_URL` | `https://git.vdm.dev` | Gitea base URL. |
| `GITEA_PACKAGE_OWNER` | unset | Gitea package owner. |
| `GITEA_PACKAGE_USER` | unset | Dedicated publishing user. |
| `GITEA_PACKAGE_TOKEN` | unset | Runtime-only package-write token. |

## Import and use

Copy or download all files for one variant, then import them on an Incus host:

```bash
./scripts/import-image-package.sh /absolute/path/to/package
incus --project vdm-agents image list
./scripts/launch-vm.sh php opencode-llewellyn
```

Runtime GitHub, Gitea MCP, model, and other authentication is added only when starting a VM session. It is not embedded in released images.
