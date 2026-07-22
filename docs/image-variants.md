# Image variants

## Common base

Every image includes Git, OpenCode, Node.js, Python runtime support, `uv`, `jq`, shell tooling, the common agents,
managed OpenCode policy and local Git MCP.

Python is present in the base only because the Git MCP reference server is Python-based. The Python project image
adds development and quality tooling.

## PHP

Adds PHP CLI extensions, Composer and MariaDB client. It also adds Chromium and Playwright because Joomla and JCB
work normally requires browser verification.

## Python

Adds Python headers, pytest, Ruff and mypy.

## C/C++

Adds Clang, clang-tidy, CMake, Ninja, GDB, LLDB, Valgrind, cppcheck and gcovr.

## TypeScript

Adds TypeScript, tsx, Playwright MCP, Playwright and Chromium.

## Full

Adds every language toolchain and Java 21. Use this only when a repository genuinely needs the combined stack.

## Adding a variant

1. Add a provisioning script under `image/provision`.
2. Add a profile under `incus/profiles`.
3. Add the variant to `manifest/images.yaml`.
4. Extend `variant_exists` and the build matrix.
5. Add smoke tests.
6. Build from a clean base and record the resulting tool versions.
