terraform {
  required_version = ">= 1.5"

  backend "azurerm" {
    # Partial config — filled by CI (-backend-config=…) or local init.
    use_azuread_auth = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  subscription_id                 = var.subscription_id
  resource_provider_registrations = "extended"
  use_oidc                        = var.use_oidc
  storage_use_azuread             = true
}

provider "azapi" {
  use_oidc = var.use_oidc
}

provider "azuread" {
  use_oidc = var.use_oidc
}

data "azurerm_client_config" "current" {}
