terraform {

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.0"
    }
  }
}

provider "azurerm" {
  features {}
  resource_provider_registrations = ["core", "Microsoft.CognitiveServices"]
  use_oidc        = true

}

provider "azapi" {
  use_oidc = true
}