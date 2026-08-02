output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.rg.name
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = azurerm_resource_group.rg.location
}

output "location_short" {
  description = "Short location code used in resource names (e.g. plc, weu)"
  value       = local.location_short
}

output "vnet_id" {
  description = "The ID of the virtual network"
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "The name of the virtual network"
  value       = azurerm_virtual_network.vnet.name
}

output "subnet_id" {
  description = "The ID of the subnet"
  value       = azurerm_subnet.subnet.id
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.law.id
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.law.name
}

# Application Insights outputs
output "application_insights_id" {
  description = "The ID of the Application Insights resource"
  value       = azurerm_application_insights.appinsights.id
}

output "application_insights_name" {
  description = "The name of the Application Insights resource"
  value       = azurerm_application_insights.appinsights.name
}

output "application_insights_app_id" {
  description = "The App ID of the Application Insights resource"
  value       = azurerm_application_insights.appinsights.app_id
}

output "application_insights_instrumentation_key" {
  description = "The Instrumentation Key of the Application Insights resource"
  value       = azurerm_application_insights.appinsights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The Connection String of the Application Insights resource"
  value       = azurerm_application_insights.appinsights.connection_string
  sensitive   = true
}

output "foundry_id" {
  description = "The ID of the Microsoft Foundry Cognitive Account"
  value       = azurerm_cognitive_account.foundry.id
}

output "foundry_name" {
  description = "The name of the Microsoft Foundry Cognitive Account"
  value       = azurerm_cognitive_account.foundry.name
}

output "foundry_endpoint" {
  description = "The endpoint of the Microsoft Foundry Cognitive Account"
  value       = azurerm_cognitive_account.foundry.endpoint
}

output "foundry_primary_access_key" {
  description = "The primary access key of the Microsoft Foundry Cognitive Account"
  value       = azurerm_cognitive_account.foundry.primary_access_key
  sensitive   = true
}

output "foundry_secondary_access_key" {
  description = "The secondary access key of the Microsoft Foundry Cognitive Account"
  value       = azurerm_cognitive_account.foundry.secondary_access_key
  sensitive   = true
}

output "foundry_user_role_assignment_id" {
  description = "The ID of the Foundry User role assignment on the Cognitive Account"
  value       = azurerm_role_assignment.foundry_user.id
}

output "foundry_principal_id" {
  description = "The principal ID of the Microsoft Foundry account system-assigned managed identity"
  value       = azurerm_cognitive_account.foundry.identity[0].principal_id
}

