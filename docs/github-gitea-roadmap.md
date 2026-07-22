# GitHub and Gitea operating roadmap

## Recommended immediate model

Use GitHub as the current source and review authority while keeping Gitea as an artifact destination and future
source mirror.

- GitHub hosts `master`, pull requests and workflow definitions.
- A self-hosted runner with Incus and hardware virtualisation builds images.
- GitHub Actions artifacts provide immediate downloadable packages for each image variant.
- Gitea Generic Packages remain the durable internal package authority when explicitly enabled.
- Gitea MCP remains available to agent VMs through the trusted MCP gateway.

This model requires no immediate repository move and preserves the Gitea investment.

## Required GitHub setup

1. Register a dedicated self-hosted Linux runner on a trusted Incus host.
2. Add runner labels `linux` and `incus`.
3. Give the runner account passwordless access only to the Incus operations required by the build scripts.
4. Protect `master` and require the validation workflow.
5. Run `Build Incus images` manually for the first verification.
6. Confirm all six artifact archives download and their `SHA256SUMS` files verify.
7. For tagged Gitea publishing, configure:
   - repository variable `GITEA_PUBLISH_ENABLED=true`;
   - repository variable `GITEA_PACKAGE_OWNER`;
   - optional repository variable `GITEA_PACKAGE_USER`;
   - repository secret `GITEA_PACKAGE_TOKEN`.
8. Use a Gitea token limited to package writes for the intended owner.

Without `GITEA_PUBLISH_ENABLED=true`, GitHub builds and artifacts still succeed and no Gitea write is attempted.

## Moving the source authority back to Gitea

When Gitea is ready to become authoritative:

1. Create a protected Gitea repository with `master` as its default branch.
2. Mirror GitHub into Gitea and compare branch and tag SHAs.
3. Install a Gitea Actions runner on the same trusted Incus builder.
4. Copy the workflows into Gitea's supported workflow directory if the deployed Gitea version does not consume
   `.github/workflows` directly.
5. Replace GitHub artifact upload steps with Gitea artifact support or keep Generic Packages as the only durable
   output.
6. Store package variables and secrets in Gitea Actions.
7. Run validation and a complete six-variant image build from Gitea.
8. Verify package checksums and import one image into a clean Incus project.
9. Change developer remotes only after the Gitea build and restore tests pass.
10. Keep GitHub as a read-only mirror if public visibility, external collaboration or disaster recovery is useful.

## Dual-host operation

Avoid two writable authorities. Choose one push authority and mirror it one-way:

```text
authoritative Git host -> read-only mirror
authoritative Git host -> CI runner -> GitHub artifacts and/or Gitea packages
```

Tags are release identities. Never recreate or force-move a published tag on either host.

## Promotion gate

A successful build is not by itself a production promotion. Production requires immutable upstream versions,
checksums, a clean runner, guest and security tests, artifact verification, a pilot import, and a matching protected
release tag.
