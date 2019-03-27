

provider "vault" {
  # address = "VAULT_ADDR"
  # token   = "VAULT_TOKEN"
}

data "vault_generic_secret" "azure_spn" {
  # path = "azure/creds/reader"
    path = "azure/creds/contributor"
}

provider "azurerm" {
  # tenant_id       = "ARM_TENANT_ID"
  # subscription_id = "ARM_SUBSCRIPTION_ID"
  client_id       = "${data.vault_generic_secret.azure_spn.data.client_id}"
  client_secret   = "${data.vault_generic_secret.azure_spn.data.client_secret}"
}

resource "azurerm_resource_group" "test" {
  name     = "terraform-vault-rf"
  location = "centralus"

  tags {
    environment = "Production"
  }
}