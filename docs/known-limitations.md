# Verification boundaries

- Repository and native HTTPS protocol tests run without an Incus host. They
  prove validation, transport, credential handling and artifact contracts; they
  do not prove KVM, bridge ACLs or a particular company's reverse proxy.
- Production image promotion requires real builds and import/boot checks on the
  target architecture. ARM64 worker promotion remains disabled pending that
  native acceptance. Controller architecture support does not imply worker
  image qualification.
- Joomla/JCB MCP is an existing functional server. Enabled capabilities still
  depend on installed extensions, synchronized definitions, the selected user's
  ACL and the current Joomla site's state. Client configuration does not bypass
  these native controls.
- The published JoomEngine image remains independent of this platform. Its
  existing Joomla CLI and MCP interfaces are consumed unchanged. Local CLI
  availability and detached remote-job support are distinct capabilities;
  integration checks must not substitute a custom upstream image to claim
  compatibility with the published one.
- Persistent JoomEngine service deployment and native API identity provisioning
  are provided by the companion Ductor integration. Existing Joomla volumes need
  an explicit MCP migration; changing image tags alone is insufficient.
- OpenBao KV-v2 retrieval is implemented for an already authenticated controller
  token with exact read permissions. Workload authentication, the external TLS
  endpoint and downstream Joomla token rotation remain deployment-owned inputs.
  This does not claim a generic OAuth broker or automatic tokenless relay.
- Company snapshots and exported handoffs are durable outside sessions only when
  the selected source and destination storage are retained and backed up. Secret
  scanning catches common patterns, not every possible confidential value.
- Apt repositories still resolve mutable distribution inputs. Node has an exact
  package/runtime pin and its setup script is content-verified; SBOMs and signed
  package identities describe each resulting image.
