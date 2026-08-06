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
    # App Insights auto-creates "Application Insights Smart Detection" action
    # groups that Terraform does not manage. Daily cleanup must delete the RG
    # even when those leftovers remain.
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    # Lab recreate cycles: permanently remove soft-deleted resources when possible.
    # Storage accounts have no purge API — Azure reserves the name ~14 days after destroy.
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    # Do NOT purge Foundry/Cognitive accounts inline on destroy.
    # With agent network injection, Azure often returns 409 "provisioning state
    # is not terminal" when purge runs immediately after delete. Workflows call
    # scripts/purge-soft-deleted-foundry.sh (wait + retry) after destroy / before apply.
    cognitive_account {
      purge_soft_delete_on_destroy = false
    }
  }
  resource_provider_registrations = "extended"
  use_oidc                        = true

}

provider "azapi" {
  use_oidc = true
}