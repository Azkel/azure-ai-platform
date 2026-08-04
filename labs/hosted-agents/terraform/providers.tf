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
  }
}

provider "azurerm" {
  features {}
  resource_provider_registrations = "extended"
  use_oidc                        = true

}

provider "azapi" {
  use_oidc = true
}