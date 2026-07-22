# Backup and migration

## Rebuildable state

The platform repository and published image packages should be enough to recreate a clean environment.

## Exact VM backup

For exceptional migration or incident recovery:

```bash
./scripts/export-instance.sh opencode-llewellyn
```

The resulting file may contain private source code, conversation state or accidentally persisted secrets. Store it
only in encrypted backup storage with restricted access.

## Import

```bash
./scripts/import-instance.sh opencode-llewellyn-YYYYMMDD.tar.zst opencode-llewellyn
```

## Preferred developer recovery

1. Launch a fresh approved image.
2. Reissue a short-lived broker identity.
3. Clone repositories.
4. Restore unpushed work from a reviewed encrypted backup only when necessary.

This keeps snowflake state from becoming the company platform.
