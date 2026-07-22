# Migration from the original one-off installer

The original installer created one `opencode-agent` VM and a host wrapper named `oc-vm`. This repository replaces
that snowflake workflow with versioned images and `occtl`.

## Preserve work

Before removing the old VM:

1. Commit all wanted repository changes.
2. Push them to temporary branches.
3. Export an encrypted VM backup only when uncommitted state must be preserved.
4. Record any agent prompt changes that should become company defaults.
5. Do not copy `auth.json`, MCP OAuth state or SSH private keys into this repository.

## Build the new platform

```bash
./scripts/bootstrap-host.sh
./scripts/build-image.sh php
./scripts/launch-vm.sh php opencode-llewellyn
```

Clone the work repositories into `/workspace` and reissue short-lived access.

## Model assignments

Run:

```bash
./scripts/configure-models.sh opencode-llewellyn
```

Model choices are configuration, not secrets, and may be standardised later by department.

## Decommission

After work is verified in the new VM:

```bash
incus --project default delete opencode-agent --force
```

Check the original project name before deletion. Keep any exact backup encrypted and subject to a retention policy.
