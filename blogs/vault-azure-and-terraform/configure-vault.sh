#!/bin/bash

# export VAULT_ADDR="http://127.0.0.1:8200"
# expprt VAULT_TOKEN=""
# export ARM_TENANT_ID=""
# export ARM_SUBSCRIPTION_ID=""
# export ARM_CLIENT_ID=""
# export ARM_CLIENT_SECRET=""

# Enable azure secrets engine
vault secrets enable \
  -path=azure \
  -description="I am description" \
  -max-lease-ttl=1h \
  -default-lease-ttl=1h \
  azure

vault write azure/config \
  tenant_id="${ARM_TENANT_ID}" \
  subscription_id="${ARM_SUBSCRIPTION_ID}" \
  client_id="${ARM_CLIENT_ID}" \
  client_secret="${ARM_CLIENT_SECRET}"

vault write azure/roles/reader ttl=1h \
  azure_roles=-<<EOF
  [
    {
      "role_name": "Reader",
      "scope":  "/subscriptions/${ARM_SUBSCRIPTION_ID}"
    }
  ]
EOF

vault write azure/roles/contributor ttl=1h \
  azure_roles=-<<EOF
  [
    {
      "role_name": "Contributor",
      "scope":  "/subscriptions/${ARM_SUBSCRIPTION_ID}"
    }
  ]
EOF
