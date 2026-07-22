# Scaling and operations

## Local workstations

High-end laptops can host one or more specialised VMs. Keep inactive VMs stopped and use project-specific clones.

## Central servers

Use:

- a dedicated Incus project for developers;
- a separate project for CI builders;
- a separate project for disposable autonomous sessions;
- storage and CPU quotas;
- central image cache;
- broker-only runtime network routes;
- per-user or per-team audit identity.

## Incus cluster

A cluster is appropriate when workloads need high aggregate capacity and central scheduling. Do not treat cluster
membership as a credential boundary; use projects, network segmentation and service identity as well.

## Rollout

1. Build versioned images.
2. Run smoke and security tests.
3. Pilot with one developer.
4. Promote the version.
5. Launch new VMs rather than mutating every old VM.
6. Push work to Git branches.
7. Retire old VMs after a defined grace period.

## Parallel agents

Run separate VMs or worktrees for independent tasks. Avoid multiple autonomous agents writing to the same
worktree. Merge through pull requests and CI.
