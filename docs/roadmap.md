# Integration and release work

The current integration replaces the retired TypeScript Joomla adapter with
native Joomla/JCB MCP, carries a verified Node runtime identity into Ductor,
adds exact private-service routes, retrieves scoped runtime values from OpenBao,
and maintains company standards in a durable Git source with review handoffs.
JCB MCP functionality is available and is consumed through its existing server.

Ductor owns persistent service deployment; this project owns the image supply
chain and standalone worker lifecycle. Crabbox-owned workers do not receive the
standalone session expiry metadata. An operator's external proxy owns domain/TLS.

Before publishing an image release, run the repository suite, native HTTP tests,
package signature and tamper tests, build the selected images on actual Incus
hosts and verify import on the destination architecture. ARM64 promotion remains
disabled until a native image build/import has been qualified. Hosted controller
or Docker tests do not prove an Incus VM's runtime networking.

Acceptance covers the intended flow: persistent JoomEngine MCP service, scoped
agent identity, an authorized JCB task, durable results for a second worker,
denied out-of-scope calls, reconnect handling and operation with Ductor offline.
These are functional correctness checks. Comparative cost, productivity and ROI
measurement are outside this implementation milestone.
