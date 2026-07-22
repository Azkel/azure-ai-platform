output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.rg.name
}

output "resource_group_location" {
  description = "The location of the resource group"
  value       = azurerm_resource_group.rg.location
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