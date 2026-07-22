# Reference policy only.
# Agent VMs should not read upstream provider or infrastructure secrets directly.
# A trusted broker exchanges this short-lived identity for narrow gateway capabilities.

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
