terraform {

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    # Lab recreate cycles: permanently remove soft-deleted resources when possible.
    # Storage accounts have no purge API — Azure reserves the name ~14 days after destroy.
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
  resource_provider_registrations = "extended"
  use_oidc                        = true

}

provider "azapi" {
  use_oidc = true
}