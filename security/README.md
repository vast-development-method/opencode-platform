# Release signing

Production releases use Cosign with an OpenBao Transit key:
`openbao://vdm-opencode-release`. Export the public verification key to the
secured deployment configuration and pass its path as `COSIGN_PUBLIC_KEY`.

The private key must never leave OpenBao. CI receives a short-lived,
sign-only OpenBao token through its runtime secret store. Private repository
builds disable public transparency-log upload to avoid disclosing digests.
