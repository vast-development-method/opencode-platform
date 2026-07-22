# The release job can inspect the public key and ask Transit to sign digests.
# It cannot export key material or read unrelated secrets.
path "transit/keys/vdm-opencode-release" {
  capabilities = ["read"]
}

path "transit/sign/vdm-opencode-release/*" {
  capabilities = ["update"]
}
