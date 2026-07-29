# Composable images, capabilities, policies and sizes

`manifest/images.yaml` is the sole platform authority. Run
`python3 scripts/generate-platform.py --write` after an intentional manifest
change; validation fails when any derived profile, shell list, version or CI
matrix is stale.

## Release images

- `base`: shell-oriented analysis and documentation.
- `php`: PHP/Joomla/JCB plus Node, TypeScript, browser, database clients and JoomEngine MCP for Joomla.
- `python`: Python development, quality tools and MCP services.
- `cpp`: C/C++ compilers, debuggers, build tools and analysis.
- `typescript`: Node, TypeScript, browser automation and Playwright MCP.
- `full`: the union of the ready language and packaged capabilities, including Joomla MCP.

Java, Go and Rust are intentionally absent. Android is a planned capability
whose future SDK may require a JDK internally; that will not create a general
Java development image.

## Build-time capabilities

Browser, database and `joomla-mcp` are ready composable components. The Joomla
capability installs an exact public npm release, stable local wrappers, a
configuration validator and a disabled OpenCode stdio entry. It belongs only to
the PHP and full images; adding it to another image requires an intentional
manifest change and regenerated evidence.

Android, GPU, rootless containers, GUI, audio and security tooling are
catalogued as planned so the schema can grow without inventing combinations or
claiming unfinished support.

## Runtime policies

- `offline`: no egress.
- `connected`: public Internet with private, management, link-local and
  metadata networks rejected.
- `brokered`, `restricted` and `release`: fail closed until the external
  gateway/proxy is deployed and tested.
- `lab`: experimental hardware policy requiring explicit acknowledgement.

A public HTTPS Joomla origin works with `connected`. A private Joomla origin
does not; use an approved gateway policy or a deliberate lab environment
instead of weakening the common ACL.

## Resource sizes

Tiny, small, medium, standard, large, xlarge and builder profiles are selected
at VM launch. They are independent of image composition and of the separate
manifest-owned build plans. A `standard` 16 GiB runtime profile therefore does
not cause a temporary image builder to allocate 16 GiB.

## Adding support

1. Add a component and dimension entry to `manifest/images.yaml`.
2. Keep it `planned` until provisioning, pins and verification exist.
3. Add the provisioning script and smoke/security tests.
4. Mark it `ready`, include it in the intended image, regenerate and validate.
5. Build, export, independently import and record promotion evidence.
