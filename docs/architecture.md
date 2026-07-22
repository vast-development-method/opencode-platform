# Architecture

## Control plane

The Git repository contains all declarative definitions, provisioning, agent prompts, tests, workflows and
documentation. Changes pass review before a new image version is produced.

## Artifact plane

Gitea stores:

- source configuration in Git;
- exported Incus images as Generic Packages;
- Docker/OCI images for broker services in the Container Registry;
- release metadata and checksums.

A native Incus remote can additionally cache approved images for direct launches.

## Runtime plane

Each person or automation gets a separate VM. VMs share no home directories or SSH agents.

```text
Gitea repository
      |
      v
Gitea Actions builder --> versioned Incus image --> developer/CI VM
                                                     |
                                                     v
                                      short-lived LLM and MCP gateways
```

## Image composition

All images inherit a common security and agent layer. Language variants add only their toolchain.

This avoids four unrelated snowflake installers while keeping ordinary VMs smaller than an all-in-one image.

## Credentials

Long-lived credentials remain outside the VM. The VM receives a short-lived gateway token or performs an
OpenCode-supported login inside an ephemeral XDG data directory under `/run`.

## Browser testing

PHP, TypeScript and full images contain Chromium and Playwright. Browser artifacts remain under the workspace and
must be explicitly retained or pushed to CI artifact storage.

## Scaling

Use Incus projects for organisational separation, profiles for resource classes and versioned images for rollout.
For large central installations, add an Incus cluster and a dedicated image-builder project.
