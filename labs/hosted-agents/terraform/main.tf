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
# ACR names can only contain alphanumeric characters
# Replace hyphens from workload_name (e.g., hosted-agents -> hostedagents)
locals {
  acr_safe_workload_name = replace(var.workload_name, "-", "")
}

resource "azurerm_container_registry" "acr" {
  name                = "acr${local.acr_safe_workload_name}${var.environment}plc"
  resource_group_name = module.platform_core.resource_group_name
  location            = module.platform_core.resource_group_location
  sku                 = var.acr_sku
  admin_enabled       = var.acr_admin_enabled

  # Note: ACR has soft delete enabled by default with minimum 7-day retention
  # This cannot be disabled, but resources are auto-purged after the retention period

  tags = merge({
    Environment = var.environment
    Workload    = var.workload_name
  }, var.tags)
}

# Get current Azure client configuration for RBAC
# This needs to be accessed before the Key Vault resource
data "azurerm_client_config" "current" {}

# Azure Key Vault for secrets and configuration
# Using Azure RBAC instead of access policies for simpler management in labs
resource "azurerm_key_vault" "kv" {
  name                        = "kv-${var.workload_name}-${var.environment}-plc"
  location                    = module.platform_core.resource_group_location
  resource_group_name         = module.platform_core.resource_group_name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = var.key_vault_sku
  
  # Use Azure RBAC for authorization (simpler for labs where infra is recreated often)
  rbac_authorization_enabled = true

  # Soft delete is required by Azure (minimum 7 days)
  # purge_protection_enabled = false allows purging after soft delete
  soft_delete_retention_days = 7
  purge_protection_enabled    = false

  tags = merge({
    Environment = var.environment
    Workload    = var.workload_name
  }, var.tags)
}

# Role assignment for the current user to manage Key Vault
# Using Azure RBAC instead of Key Vault access policies
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Microsoft Foundry Project
# Using azapi provider to create the project under the Foundry account
# Resource type: Microsoft.CognitiveServices/accounts/projects
# Note: In azapi v2.x+, body must be an HCL object, not a JSON string
# 
# IMPORTANT: This resource depends on the platform_core module having completed
# the azapi_update_resource.foundry_enable_projects which sets allowProjectManagement=true
# on the Foundry account. The explicit depends_on ensures proper ordering.
resource "azapi_resource" "foundry_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2026-05-01"
  name      = var.foundry_project_name
  parent_id = module.platform_core.foundry_id
  location  = module.platform_core.resource_group_location
  
  # Body as HCL object (azapi v2.x+ requires this)
  body = {
    properties = {
      description = "Hosted Agents project for ${var.workload_name} workload"
    }
  }
  
  tags = merge({
    Environment = var.environment
    Workload    = var.workload_name
  }, var.tags)
  
  # Disable schema validation to allow newer API versions
  # The azapi provider may have stricter validation than the Azure API itself
  schema_validation_enabled = false

  # Ensure Foundry User role is assigned before creating projects
  depends_on = [module.platform_core.foundry_user_role_assignment_id]
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

# Azure Key Vault outputs
output "key_vault_id" {
  description = "The ID of the Azure Key Vault"
  value       = azurerm_key_vault.kv.id
}

output "key_vault_name" {
  description = "The name of the Azure Key Vault"
  value       = azurerm_key_vault.kv.name
}

output "key_vault_uri" {
  description = "The URI of the Azure Key Vault"
  value       = azurerm_key_vault.kv.vault_uri
}

# Application Insights outputs (from platform-core module)
output "application_insights_id" {
  description = "The ID of the Application Insights resource"
  value       = module.platform_core.application_insights_id
}

output "application_insights_name" {
  description = "The name of the Application Insights resource"
  value       = module.platform_core.application_insights_name
}

output "application_insights_app_id" {
  description = "The App ID of the Application Insights resource"
  value       = module.platform_core.application_insights_app_id
}

output "application_insights_instrumentation_key" {
  description = "The Instrumentation Key of the Application Insights resource"
  value       = module.platform_core.application_insights_instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The Connection String of the Application Insights resource"
  value       = module.platform_core.application_insights_connection_string
  sensitive   = true
}

# Microsoft Foundry Project outputs
# The project endpoint is constructed from the account endpoint
# Format: {foundry_account_endpoint}/projects/{project_name}
locals {
  foundry_project_endpoint = "${module.platform_core.foundry_endpoint}/projects/${var.foundry_project_name}"
}

output "foundry_project_id" {
  description = "The ID of the Microsoft Foundry project"
  value       = azapi_resource.foundry_project.id
}

output "foundry_project_name" {
  description = "The name of the Microsoft Foundry project"
  value       = azapi_resource.foundry_project.name
}

output "foundry_project_endpoint" {
  description = "The endpoint of the Microsoft Foundry project"
  value       = local.foundry_project_endpoint
}