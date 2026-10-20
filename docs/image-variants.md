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

Browser, database and `joomla-mcp` are ready composable components. Every image
includes the native Joomla/JCB HTTP client and configuration validator. OpenCode
connects directly to approved remote sites. There is no bundled Node Joomla
server and no requirement for the PHP toolchain merely to call the service.

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
does not; use `occtl network-configure` with exact service addresses and ports,
or the explicit Ductor worker pool policy. See [private routes](service-network.md).

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
