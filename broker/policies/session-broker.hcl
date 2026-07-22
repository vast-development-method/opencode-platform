# Applied only to the trusted external session broker. Agent VMs never receive
# an OpenBao token and never access these paths.
path "secret/data/providers/*" {
  capabilities = ["read"]
}

path "pki_int/issue/agent-session" {
  capabilities = ["update"]
}

path "ssh-client-signer/sign/agent-session" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
