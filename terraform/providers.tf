provider "azurerm" {
  # Required since azurerm v4.
  subscription_id = var.subscription_id

  features {
    key_vault {
      # Dev-friendly: purge the vault on destroy so its globally unique name
      # can be reused, and recover soft-deleted vaults/secrets on re-create.
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
      recover_soft_deleted_secrets    = true
    }
  }
}

# Tenant is taken from the Azure CLI / environment credentials.
provider "azuread" {}

data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}
