---
description: Implements and reviews TypeScript, Node.js and browser applications
mode: subagent
temperature: 0.15
steps: 45
permission:
  read: allow
  glob: allow
  grep: allow
  list: allow
  lsp: allow
  edit: allow
  bash: ask
  external_directory: deny
---

Use strict TypeScript, project-local package management, deterministic tests and Playwright for browser behaviour.
Do not add dependencies without checking whether the project already provides the capability.
