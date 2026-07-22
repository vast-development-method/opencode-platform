# GitHub and Gitea operating model

## Current production shape

GitHub can host the source, validate every push and retain downloadable workflow artifacts. Incus image creation
still requires a trusted self-hosted Ubuntu machine with hardware virtualisation, Incus and sufficient storage.
Gitea remains fully supported for source hosting, Actions, its first-party MCP and durable Generic Packages.

Do not make GitHub and Gitea independently writable authorities for the same branches. Choose one source of truth
and mirror in one direction.

## Recommended migration path back to Gitea

1. Keep GitHub as the temporary writable authority while the first `0.2.x` images are proven.
2. Create a private pull mirror in Gitea from
   `https://github.com/vast-development-method/opencode-platform` using a read-only fine-grained GitHub token.
3. Enable repository Actions in Gitea.
4. Install Gitea `act_runner` on the dedicated Incus build host, not on the Gitea application server.
5. Register the image runner with the label `incus:host`; the workflow deliberately targets `runs-on: incus`.
6. Configure Gitea Actions variables `GITEA_BASE_URL`, `GITEA_PACKAGE_OWNER`, `GITEA_PACKAGE_USER` and secret
   `GITEA_PACKAGE_TOKEN`.
7. Run validation, then manually run the image workflow and import one downloaded package on a clean Incus host.
8. Freeze GitHub writes, force one final mirror sync, convert the Gitea mirror to a regular repository and make
   Gitea the writable authority.
9. Configure Gitea to push-mirror the now-authoritative repository to GitHub if GitHub visibility and Actions
   validation should remain available.

## GitHub setup

The validation workflow needs no repository secrets. For image builds, add one self-hosted runner on the Incus
builder and assign the custom label `incus`. The runner must expose `/dev/kvm`, use an Incus storage pool and have at
least the configured `MIN_BUILD_FREE_GIB` available. Keep the GitHub runner at version `2.327.1` or later because
the pinned current actions use the Node.js 24 action runtime.

For optional Gitea publication from a GitHub tag build, configure:

- variable `GITEA_PUBLISH_ENABLED=true`;
- variable `GITEA_BASE_URL=https://git.vdm.dev`;
- variables `GITEA_PACKAGE_OWNER` and `GITEA_PACKAGE_USER`;
- secret `GITEA_PACKAGE_TOKEN` with package-write scope only.

Protect `master` and require the validation workflow. For the first release candidate, manually run the image
workflow, download all six packages, verify `SHA256SUMS` in each one and import at least one package into a clean
Incus project. Tags are release identities and must never be recreated or force-moved after publication.

## Production promotion gate

A successful workflow is necessary but not sufficient for production promotion. Promote only from a clean trusted
runner after validation, the complete six-variant build, checksum verification, guest and security tests, a clean
pilot import and a matching protected release tag have all passed.

## Distribution choice

- GitHub workflow artifacts are convenient build downloads and expire according to repository retention policy.
- GitHub release assets are permanent, but each individual file must remain under 2 GiB.
- Gitea Generic Packages are the preferred durable internal image store.
- A native Incus remote is the fastest option for repeated internal launches and can be added after package
  promotion is stable.
