# Local image builds and releases

This path builds, packages, verifies and optionally publishes Incus images entirely on an in-house builder. GitHub does not need network access to the builder. The host only needs outbound access to clone the repository, obtain build dependencies and, when enabled, upload packages to Gitea.

## One-time builder setup

Use a trusted Ubuntu or Debian host with hardware virtualisation, read/write
access to `/dev/kvm`, and a supported Incus package. The bootstrap installs the
newest candidate from the host's already configured repositories. Incus LTS is
recommended for production builders; changing from the distribution package to
another supported package source is a separate operator decision.

```bash
git clone https://github.com/vast-development-method/opencode-platform.git
cd opencode-platform
cp .env.example .env
./scripts/bootstrap-host.sh
./scripts/ci/check-incus-runner.sh typescript
```

The builder does not need a GitHub Actions runner or a Gitea Actions runner.

`bootstrap-host.sh` is deliberately conservative:

- APT and dpkg must already be internally consistent.
- `/usr/bin/cp`, `/usr/bin/mv`, and `/usr/bin/rm` must exist and be executable.
- No package repository or coreutils provider is added, removed or replaced.
- If a newer Incus package would restart a daemon with running instances, the
  command stops and lists those instances. Set
  `VDM_ALLOW_INCUS_UPGRADE_WITH_RUNNING_INSTANCES=true` only during scheduled
  downtime.

## Build capacity

Build resources are distinct from launch-time runtime sizes. The manifest
defines a minimum and preferred build plan for every variant. Before it creates
or starts a VM, the builder:

- keeps the greater of 20% of total RAM or 2 GiB available to the host;
- reserves an additional 512 MiB for QEMU overhead;
- leaves at least one online CPU to the host;
- checks current `MemAvailable`, not merely installed RAM;
- does not count swap;
- checks variant disk, cache and host reserve requirements.

| Variant | Minimum build | Preferred build | Virtual disk |
|---|---:|---:|---:|
| `base` | 2 CPUs / 3 GiB | 2 CPUs / 4 GiB | 40 GiB |
| `php` | 2 CPUs / 6 GiB | 4 CPUs / 8 GiB | 100 GiB |
| `python` | 2 CPUs / 4 GiB | 4 CPUs / 6 GiB | 60 GiB |
| `cpp` | 2 CPUs / 4 GiB | 4 CPUs / 6 GiB | 100 GiB |
| `typescript` | 2 CPUs / 6 GiB | 4 CPUs / 8 GiB | 80 GiB |
| `full` | 4 CPUs / 8 GiB | 6 CPUs / 12 GiB | 160 GiB |

A 14 GiB, 4-core/8-thread laptop is sufficient for TypeScript when other
workloads leave roughly 9.5 GiB available. If only 3.4 GiB is available, the
builder reports the exact shortfall and exits before applying Incus resources.
Closing other workloads is sufficient; adding swap is not a repository
requirement.

## Caching, resume and clean builds

The default managed `vdm-build-cache` volume retains only package/browser
downloads. Package managers still perform their normal signature and integrity
checks. The volume is detached before verification is published, so it is not
part of the image.

If a build fails, the VM is stopped rather than destroyed. Completed stages
resume when the same source and variant are run again, and a non-secret
diagnostic bundle is written under `build/diagnostics/`.

```bash
# Resume the exact retained checkpoint.
./scripts/build-image.sh typescript

# Discard that checkpoint but retain verified download caches.
./scripts/build-image.sh --clean typescript

# Independent clean-room evidence: no checkpoint and no shared cache.
./scripts/build-image.sh --clean --no-cache typescript
```

Successful builds delete their temporary VM automatically. The managed cache
remains bounded by the manifest.

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

The PHP and full images include the exact Joomla MCP package recorded in
`manifest/toolchain.env`. They contain only a read-only example and a disabled
OpenCode entry; no active Joomla origin or credential is part of a package.

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

The package names are `vdm-opencode-<variant>`, and the package version is read
from `VERSION` and `manifest/generated/platform.env`. The command refuses to
run if those versions disagree.

## Production tagged release

For a reproducible production release, build the exact protected tag and require both a clean checkout and the matching tag:

```bash
git fetch --tags --prune origin
git switch --detach v0.3.0-rc.3

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

Replace `v0.3.0-rc.3` with the version being released. Tags must not be recreated or force-moved after packages are published.

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
| `MIN_BUILD_FREE_GIB` | `0` | Optional disk floor; zero uses the variant-specific manifest requirement. |
| `VDM_BUILD_CACHE` | `true` | Reuse the managed package/browser download cache. |
| `MIN_INCUS_VERSION` | `6.0.5` | Oldest supported Incus server; bootstrap still installs the newest configured candidate. |

## Import and use

Copy or download all files for one variant, then import them on an Incus host:

```bash
./scripts/import-image-package.sh /absolute/path/to/package
incus --project vdm-agents image list
./scripts/launch-vm.sh php opencode-llewellyn
```

Configure the Joomla origin only after launch with `occtl joomla-configure`.
Runtime GitHub, Gitea, Joomla, model and other authentication is added only
when starting a bounded VM session. It is not embedded in released images.
