# Company standards and review handoffs

Company knowledge belongs in an independently retained Git repository. The
worker receives a verified snapshot of selected instructions; ending a session,
stopping Ductor or deleting a worker does not delete the authoritative source.
Keep secrets out of this repository. Put team standards, preferred technologies,
project decisions and links to established work in reviewed Markdown documents.

At the root of that repository, commit `company-context.json`:

```json
{
  "schema": 1,
  "name": "Company engineering standards",
  "instructions": [
    "standards/engineering.md",
    "standards/review.md",
    "projects/current-objectives.md"
  ]
}
```

These paths describe operator-authored documents, not standards invented by this
platform. Create and commit the selected documents with your actual policies.
Only committed, explicitly selected Markdown files are loaded. Untracked files
and local edits cannot accidentally become company instructions. A selected
document can be at most 1 MiB; a snapshot can contain 128 documents and 8 MiB.

Synchronize a reviewed local checkout into a worker:

```bash
./scripts/occtl.sh company-sync opencode-joomla /srv/company-standards
```

An optional third argument selects a commit or ref. `HEAD` is the default and is
resolved once to its full commit identity before any content is transferred.
The output records that commit and the content-addressed snapshot identity.
Reusing the same exact commit produces the same snapshot. The company repository
does not need to be copied into the worker or exposed to its network.

Guest documents live beneath `/etc/vdm-opencode/company/snapshots/`, are owned by
root and are read-only to the agent. Synchronization adds their explicit paths
to OpenCode's `instructions` array while preserving unrelated instruction
entries, MCP definitions and the rest of the existing configuration. Workspace
`AGENTS.md` files are not overwritten. Older snapshots remain available for
provenance; only the active snapshot is loaded. Synchronize again after an
approved standards change and start a new agent session to load it.

Session preflight verifies file ownership, content hashes, provenance and the
managed OpenCode instruction entries. A damaged or incomplete configured
snapshot fails rather than silently dropping the company's instructions.
Instruction documents guide model behavior; they do not replace system-level
permissions, Joomla ACL or approval requirements.

## Preserve results for the next worker

Ask a worker to write a review handoff describing the task, decisions, changed
repositories/commits, checks performed, artifact references, unresolved matters
and the next action. Keep it in the workspace, then export explicit files to a
durable host directory before deleting the worker:

```bash
./scripts/occtl.sh handoff-export opencode-joomla \
  /srv/company-handoffs/project-review-001 \
  review/outcome.md review/changes.patch .artifacts/compile/component.zip
```

The destination must be new, below an existing directory owned by the caller
and not writable by other users. Files use private permissions. The resulting
`handoff.json` records checksums, sizes and company snapshot provenance; files
are stored beneath `files/`. Retain that directory in your existing backup or
reviewed artifact repository. Commit accepted findings back to the company or
project knowledge repository and include the relevant documents in its next
snapshot. That makes subsequent workers start with the reviewed outcome.

Export allows only explicitly selected Markdown, text, JSON, XML, CSV, patches,
diffs and ZIP artifacts. It never recursively copies a workspace, runtime
directory, home directory or credential store. Up to 128 files, 16 MiB per file
and 64 MiB total are accepted. ZIP members are also checked for traversal,
credentials, symlinks, encryption, nested ZIPs and excessive expansion. The
source is read as the unprivileged agent using descriptor-relative no-follow
opens, so replacing a selected file with a symlink cannot redirect the transfer
to a privileged file. Both ends validate content hashes and permitted paths.

Common credential patterns are rejected, but automatic scanning cannot identify
every possible secret. Review selected artifacts before sharing them. Never put
runtime tokens into project outputs. Export is explicit and does not publish or
push anything to a remote repository automatically.

Shared JoomEngine, OpenClaw and OpenBao services belong in persistent service
VMs. The worker expiry reaper may stop disposable agent VMs; it must never own
the lifecycle of those shared services. Company source and retained handoffs
must likewise live outside those disposable VMs.
