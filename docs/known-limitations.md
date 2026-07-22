# Known limitations

- The repository has been statically validated, but the image build was not executed in this delivery environment
  because nested Incus and external package downloads are unavailable here.
- Upstream tool versions still contain development-channel floating references.
- The Nextcloud candidate has not received a VDM security audit.
- The VDM Joomla MCP is not yet released and its generic platform hook remains disabled.
- JCB MCP has no approved release.
- The reference broker does not yet implement the company MCP authorization gateway.
- Incus ACLs currently provide inbound isolation but not strict DNS-aware outbound filtering.
- Image builds require a self-hosted runner with Incus access and hardware virtualization on either GitHub or Gitea.
- GitHub Actions artifacts are retained for 30 days; use Gitea Generic Packages for durable internal retention.
- OpenCode config compatibility should be revalidated whenever OpenCode is upgraded.
