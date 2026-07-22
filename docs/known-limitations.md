# Known limitations

- The repository has been statically validated, but the image build was not executed in this delivery environment
  because nested Incus and external package downloads are unavailable here.
- Upstream tool versions still contain development-channel floating references.
- The Nextcloud candidate has not received a VDM security audit.
- No Joomla MCP candidate is enabled.
- JCB MCP has no approved release.
- The reference broker does not yet implement the company MCP authorization gateway.
- Incus ACLs currently provide inbound isolation but not strict DNS-aware outbound filtering.
- Gitea Actions require a self-hosted runner with Incus access and hardware virtualization.
- OpenCode config compatibility should be revalidated whenever OpenCode is upgraded.
