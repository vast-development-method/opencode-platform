# Known limitations

- The repository has been statically validated, but the image build was not executed in this delivery environment
  because nested Incus and external package downloads are unavailable here.
- Ubuntu/Node/PHP system packages are resolved from the configured repositories at build time; their exact installed
  versions are recorded inside each image manifest but are not yet sourced from a company snapshot mirror.
- The Nextcloud candidate has not received a VDM security audit.
- The VDM Joomla MCP and JCB MCP are intentionally not installed pending their first approved releases.
- The reference broker does not yet implement the company MCP authorization gateway.
- Incus ACLs currently provide inbound isolation but not strict DNS-aware outbound filtering.
- GitHub image builds require a self-hosted runner labelled `self-hosted`, `linux`, `incus`. Gitea image builds
  require a host runner labelled `incus:host`.
- OpenCode config compatibility should be revalidated whenever OpenCode is upgraded.
