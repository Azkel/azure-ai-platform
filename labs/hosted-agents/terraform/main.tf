terraform {
  backend "azurerm" {
    # Backend configuration will be provided via environment variables
    # in the GitHub Actions workflow
    use_azuread_auth = true
  }
}

module "platform_core" {
  source = "../../shared-modules/platform-core"

  workload_name = "hosted-agents"
  location      = "polandcentral"
  environment   = var.environment

  # VNet configuration
  vnet_address_space      = ["10.1.0.0/16"]
  subnet_address_prefixes = ["10.1.1.0/24"]

  # Log Analytics configuration
  log_analytics_sku               = "PerGB2018"
  log_analytics_retention_in_days = 30 # Cost-optimized for labs

  # Microsoft Foundry configuration
  foundry_sku = "S0" # Cost-optimized for labs; use F0 or higher for production

}

# Azure Container Registry for hosted-agents workload
resource "azurerm_container_registry" "acr" {
  name                = "acr${var.workload_name}${var.environment}plc"
  resource_group_name = module.platform_core.resource_group_name
  location            = module.platform_core.resource_group_location
  sku                 = var.acr_sku
  admin_enabled       = var.acr_admin_enabled

  tags = merge({
    Environment = var.environment
    Workload    = var.workload_name
  }, var.tags)
}

# Output the core resources that will be used by other modules
output "resource_group_name" {
  value = module.platform_core.resource_group_name
}

output "vnet_id" {
  value = module.platform_core.vnet_id
}

output "subnet_id" {
  value = module.platform_core.subnet_id
}

output "log_analytics_workspace_id" {
  value = module.platform_core.log_analytics_workspace_id
}

# Microsoft Foundry outputs
output "foundry_id" {
  description = "The ID of the Microsoft Foundry account"
  value       = module.platform_core.foundry_id
}

output "foundry_name" {
  description = "The name of the Microsoft Foundry account"
  value       = module.platform_core.foundry_name
}

output "foundry_endpoint" {
  description = "The endpoint of the Microsoft Foundry account"
  value       = module.platform_core.foundry_endpoint
  sensitive   = true
}

# Azure Container Registry outputs
output "container_registry_id" {
  description = "The ID of the Azure Container Registry"
  value       = azurerm_container_registry.acr.id
}

output "container_registry_name" {
  description = "The name of the Azure Container Registry"
  value       = azurerm_container_registry.acr.name
}

output "container_registry_login_server" {
  description = "The login server URL of the Azure Container Registry"
  value       = azurerm_container_registry.acr.login_server
}

output "container_registry_admin_username" {
  description = "The admin username of the Azure Container Registry"
  value       = azurerm_container_registry.acr.admin_username
  sensitive   = true
}

output "container_registry_admin_password" {
  description = "The admin password of the Azure Container Registry"
  value       = azurerm_container_registry.acr.admin_password
  sensitive   = true
}