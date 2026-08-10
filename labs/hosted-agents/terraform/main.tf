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
  location      = "westeurope"
  environment   = local.environment

  # VNet configuration (172.16/16 works in all Agent Service regions, including
  # those without Class A / 10.x support such as Poland Central).
  vnet_address_space      = ["172.16.0.0/16"]
  subnet_address_prefixes = ["172.16.1.0/24"]

  # Log Analytics configuration
  log_analytics_sku               = "PerGB2018"
  log_analytics_retention_in_days = 30 # Cost-optimized for labs

  # Microsoft Foundry configuration
  foundry_sku                             = "S0" # Cost-optimized for labs
  additional_foundry_user_principal_ids   = var.additional_foundry_user_principal_ids
  foundry_agent_network_injection_enabled = true
}

# Azure Container Registry for hosted-agents workload
# ACR names can only contain alphanumeric characters
# Replace hyphens from workload_name (e.g., hosted-agents -> hostedagents)
locals {
  # Single lab environment — naming stays "dev" for stable resource names.
  environment            = "dev"
  acr_safe_workload_name = replace(var.workload_name, "-", "")
  location_short         = module.platform_core.location_short
  # Storage account names: 3–24 lowercase alphanumeric.
  # Base "st{workload}{env}{loc}" is 20 chars for this lab; +4 digits = 24 (Azure max).
  # Random suffix avoids the ~14-day soft-delete name reservation after destroy.
  storage_account_name = "st${local.acr_safe_workload_name}${local.environment}${local.location_short}${random_integer.storage_suffix.result}"
}

# New value on each fresh apply after destroy (resource is removed with state).
resource "random_integer" "storage_suffix" {
  min = 1000
  max = 9999
}

resource "azurerm_container_registry" "acr" {
  name                = "acr${local.acr_safe_workload_name}${local.environment}${local.location_short}"
  resource_group_name = module.platform_core.resource_group_name
  location            = module.platform_core.resource_group_location
  sku                 = var.acr_sku
  admin_enabled       = var.acr_admin_enabled

  # Note: ACR has soft delete enabled by default with minimum 7-day retention
  # This cannot be disabled, but resources are auto-purged after the retention period

  tags = merge({
    Environment = local.environment
    Workload    = var.workload_name
  }, var.tags)
}

# Get current Azure client configuration for RBAC
# This needs to be accessed before the Key Vault resource
data "azurerm_client_config" "current" {}

# Azure Key Vault for secrets and configuration
# Using Azure RBAC instead of access policies for simpler management in labs
resource "azurerm_key_vault" "kv" {
  name                        = "kv-${var.workload_name}-${local.environment}-${local.location_short}"
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
  purge_protection_enabled   = false

  tags = merge({
    Environment = local.environment
    Workload    = var.workload_name
  }, var.tags)
}

# Role assignment for the current deployer to manage Key Vault
# Using Azure RBAC instead of Key Vault access policies
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Keep interactive operators / extra identities as KV admins when CI applies
# (current.object_id is the GitHub OIDC app in Actions, not the human user).
resource "azurerm_role_assignment" "additional_kv_admins" {
  for_each = toset(var.additional_key_vault_admin_principal_ids)

  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = each.value
}

# App Insights connection string in Key Vault (local / ops lookups).
# Hosted agents do NOT read this secret themselves — Foundry injects
# APPLICATIONINSIGHTS_CONNECTION_STRING from the project AppInsights connection
# created below. Do not declare that env var in azure.yaml.
resource "azurerm_key_vault_secret" "appinsights_connection_string" {
  name         = "applicationinsights-connection-string"
  value        = module.platform_core.application_insights_connection_string
  key_vault_id = azurerm_key_vault.kv.id
  content_type = "text/plain"

  tags = merge({
    Environment = local.environment
    Workload    = var.workload_name
    Purpose     = "app-insights"
  }, var.tags)

  depends_on = [
    azurerm_role_assignment.kv_admin,
    azurerm_role_assignment.additional_kv_admins,
  ]
}

# User-provided demo secret read by the hosted agent via SecretClient + MI.
# Override agent_demo_secret_value (TF var / CI) or update the secret in portal/CLI.
resource "azurerm_key_vault_secret" "agent_demo_message" {
  name         = var.agent_demo_secret_name
  value        = var.agent_demo_secret_value
  key_vault_id = azurerm_key_vault.kv.id
  content_type = "text/plain"

  tags = merge({
    Environment = local.environment
    Workload    = var.workload_name
    Purpose     = "agent-demo"
  }, var.tags)

  depends_on = [
    azurerm_role_assignment.kv_admin,
    azurerm_role_assignment.additional_kv_admins,
  ]
}

# Workload storage for agent note persistence (Azure AD auth only — no account keys).
# Soft-delete notes:
# - Blob/container soft-delete is left disabled (no delete_retention_policy) so
#   terraform destroy removes data with the account rather than retaining soft-deleted blobs.
# - Azure still soft-deletes the *account* for ~14 days after destroy and does not
#   expose a purge API (unlike Key Vault). A 4-digit random suffix keeps recreates
#   from colliding with the reserved name:
#   https://learn.microsoft.com/en-us/azure/storage/common/storage-account-recover
resource "azurerm_storage_account" "agent_data" {
  name                            = local.storage_account_name
  resource_group_name             = module.platform_core.resource_group_name
  location                        = module.platform_core.resource_group_location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  public_network_access_enabled   = true

  blob_properties {
    versioning_enabled  = false
    change_feed_enabled = false
    # Intentionally omit delete_retention_policy / container_delete_retention_policy
    # and restore_policy so soft-deleted blobs/containers are not retained.
  }

  tags = merge({
    Environment = local.environment
    Workload    = var.workload_name
    Purpose     = "agent-data"
  }, var.tags)

  lifecycle {
    precondition {
      condition     = length(local.storage_account_name) >= 3 && length(local.storage_account_name) <= 24
      error_message = "Storage account name '${local.storage_account_name}' must be 3–24 characters (Azure limit)."
    }
  }
}

resource "azurerm_storage_container" "agent_notes" {
  name                  = var.storage_blob_container_name
  storage_account_id    = azurerm_storage_account.agent_data.id
  container_access_type = "private"
}

# Local developers / operators can read/write blobs when listed here.
# The hosted agent's instance identity is assigned Storage Blob Data Contributor
# after azd deploy (see docker-build-push-hosted-agents.yml) because that
# principal is created at agent deploy time, not by Terraform.
resource "azurerm_role_assignment" "additional_storage_blob_data_contributors" {
  for_each = toset(var.additional_storage_blob_data_contributor_principal_ids)

  scope                = azurerm_storage_account.agent_data.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "additional_kv_secrets_users" {
  for_each = toset(var.additional_key_vault_secrets_user_principal_ids)

  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}

# Microsoft Foundry Project
# Using azapi provider to create the project under the Foundry account
# Resource type: Microsoft.CognitiveServices/accounts/projects
# Note: In azapi v2.x+, body must be an HCL object, not a JSON string
#
# IMPORTANT: Create the account-scoped model deployment BEFORE the project.
# Concurrent PUTs on the Cognitive account (deployment + project) frequently
# return 409 RequestConflict: "Another operation is in progress on the resource"
# (see Actions run 31385851423). depends_on serializes; retry covers residual races.
resource "azapi_resource" "foundry_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2026-05-01"
  name      = var.foundry_project_name
  parent_id = module.platform_core.foundry_id
  location  = module.platform_core.resource_group_location

  # Body as HCL object (azapi v2.x+ requires this)
  # Projects require a managed identity (SystemAssigned) per Foundry API
  body = {
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      description = "Hosted Agents project for ${var.workload_name} workload"
    }
  }

  tags = merge({
    Environment = local.environment
    Workload    = var.workload_name
  }, var.tags)

  # Disable schema validation to allow newer API versions
  # The azapi provider may have stricter validation than the Azure API itself
  schema_validation_enabled = false

  # Export identity so we can grant ACR pull to the project MI
  response_export_values = ["identity"]

  retry = {
    error_message_regex = [
      "RequestConflict",
      "Another operation is in progress",
      "AnotherOperationInProgress",
    ]
    interval_seconds     = 20
    max_interval_seconds = 180
    multiplier           = 1.5
    randomization_factor = 0.5
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [
    module.platform_core.foundry_user_role_assignment_id,
    azurerm_cognitive_deployment.agent_model,
    azurerm_role_assignment.foundry_account_acr_pull,
    azurerm_role_assignment.foundry_account_acr_repo_reader,
    azurerm_role_assignment.foundry_account_kv_secrets_user,
  ]
}

# Model deployment used by the hosted agent (AZURE_AI_MODEL_DEPLOYMENT_NAME).
# Account-scoped on the Foundry AIServices resource — required before agent invoke.
resource "azurerm_cognitive_deployment" "agent_model" {
  name                 = var.model_deployment_name
  cognitive_account_id = module.platform_core.foundry_id

  model {
    format  = var.model_format
    name    = var.model_name
    version = var.model_version
  }

  sku {
    name     = var.model_sku_name
    capacity = var.model_sku_capacity
  }

  depends_on = [module.platform_core]
}

locals {
  foundry_project_principal_id = azapi_resource.foundry_project.output.identity.principalId
}

# Link platform App Insights to the Foundry project so hosted agents receive
# APPLICATIONINSIGHTS_CONNECTION_STRING at runtime (OpenTelemetry via AgentServer).
# Without this connection the App Insights resource exists but agents stay dark.
resource "azapi_resource" "foundry_project_appinsights_connection" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = module.platform_core.application_insights_name
  parent_id                 = azapi_resource.foundry_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      category = "AppInsights"
      target   = module.platform_core.application_insights_id
      authType = "ApiKey"
      credentials = {
        key = module.platform_core.application_insights_connection_string
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = module.platform_core.application_insights_id
      }
    }
  }

  depends_on = [azapi_resource.foundry_project]
}

# Account-level Agents capability host is auto-created when the Foundry account
# is provisioned with network_injection.scenario=agent (name like
# "{account}@aml_aiagentservice"). Do not create a second account host.

# Project-level Agents capability host (required for agent runtime routing).
# Must NOT include customerSubnet (API rejects subnet at project scope).
resource "azapi_resource" "foundry_project_capability_host" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-06-01"
  name                      = "caphost"
  parent_id                 = azapi_resource.foundry_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind = "Agents"
    }
  }

  depends_on = [
    azapi_resource.foundry_project,
    azapi_resource.foundry_project_appinsights_connection,
  ]
}

# Project MI pulls the hosted-agent image from ACR at deploy/runtime.
# Prefer Repository Reader (data plane); also grant AcrPull for registries
# still on classic RBAC mode.
resource "azurerm_role_assignment" "foundry_project_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = local.foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_project_acr_repo_reader" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "Container Registry Repository Reader"
  principal_id         = local.foundry_project_principal_id
}

# Account MI is also observed to participate in hosted-agent image pulls.
resource "azurerm_role_assignment" "foundry_account_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = module.platform_core.foundry_principal_id
}

resource "azurerm_role_assignment" "foundry_account_acr_repo_reader" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "Container Registry Repository Reader"
  principal_id         = module.platform_core.foundry_principal_id
}

# Foundry identities need Key Vault Secrets User for vault secrets used by
# lab ops (e.g. demo message, App Insights connection string backup).
# Agent telemetry itself uses the project AppInsights connection, not this vault.
resource "azurerm_role_assignment" "foundry_project_kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = local.foundry_project_principal_id
}

resource "azurerm_role_assignment" "foundry_account_kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.platform_core.foundry_principal_id
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

output "appinsights_connection_string_secret_name" {
  description = "Key Vault secret name for the Application Insights connection string"
  value       = azurerm_key_vault_secret.appinsights_connection_string.name
}

output "appinsights_connection_string_secret_id" {
  description = "Key Vault secret resource ID for the Application Insights connection string"
  value       = azurerm_key_vault_secret.appinsights_connection_string.id
  sensitive   = true
}

output "agent_demo_secret_name" {
  description = "Key Vault secret name read by the hosted agent at runtime"
  value       = azurerm_key_vault_secret.agent_demo_message.name
}

# Azure Storage outputs (agent data plane via managed identity)
output "storage_account_id" {
  description = "The ID of the agent data storage account"
  value       = azurerm_storage_account.agent_data.id
}

output "storage_account_name" {
  description = "The name of the agent data storage account"
  value       = azurerm_storage_account.agent_data.name
}

output "storage_blob_endpoint" {
  description = "Blob endpoint of the agent data storage account"
  value       = azurerm_storage_account.agent_data.primary_blob_endpoint
}

output "storage_blob_container_name" {
  description = "Blob container used by the hosted agent for notes"
  value       = azurerm_storage_container.agent_notes.name
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

output "model_deployment_name" {
  description = "Foundry model deployment name used by the hosted agent"
  value       = azurerm_cognitive_deployment.agent_model.name
}

output "model_deployment_id" {
  description = "Resource ID of the Foundry model deployment"
  value       = azurerm_cognitive_deployment.agent_model.id
}
