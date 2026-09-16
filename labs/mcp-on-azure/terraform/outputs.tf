output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "location" {
  value = azurerm_resource_group.rg.location
}

output "container_app_fqdn" {
  description = "Public FQDN of the MCP Container App (Entra auth comes in Phase 3)"
  value       = azurerm_container_app.mcp.ingress[0].fqdn
}

output "container_app_name" {
  value = azurerm_container_app.mcp.name
}

output "container_app_environment_name" {
  value = azurerm_container_app_environment.cae.name
}

output "container_app_principal_id" {
  description = "System-assigned MI of the MCP app — used by platform.* tools"
  value       = azurerm_container_app.mcp.identity[0].principal_id
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "storage_account_name" {
  value = azurerm_storage_account.demo.name
}

output "storage_container_name" {
  value = azurerm_storage_container.demo.name
}

output "storage_platform_only_container_name" {
  description = "Container seeded with platform-only.txt — user.* should get 403"
  value       = azurerm_storage_container.platform_only.name
}

output "application_insights_connection_string" {
  value     = azurerm_application_insights.appi.connection_string
  sensitive = true
}

output "mcp_endpoint" {
  description = "Base URL for the MCP server (custom hostname when configured)"
  value       = local.custom_domain_enabled ? "https://${var.custom_hostname}" : "https://${azurerm_container_app.mcp.ingress[0].fqdn}"
}

output "mcp_default_fqdn" {
  description = "Built-in Container Apps FQDN"
  value       = azurerm_container_app.mcp.ingress[0].fqdn
}

output "custom_hostname" {
  value = local.custom_domain_enabled ? var.custom_hostname : null
}

output "entra_client_id" {
  description = "Entra app (client) ID for MCP Easy Auth / token audience"
  value       = local.entra_enabled ? azuread_application.mcp[0].client_id : null
}

output "entra_tenant_id" {
  value = local.entra_enabled ? data.azurerm_client_config.current.tenant_id : null
}

output "entra_scope" {
  description = "Scope to request when acquiring a user token for the MCP API"
  value = local.entra_enabled ? (
    local.custom_domain_enabled
    ? "https://${var.custom_hostname}/mcp/access_as_user"
    : "api://mcp-on-azure-${local.environment}-${local.location_short}/access_as_user"
  ) : null
}

output "entra_resource" {
  description = "OAuth resource / Application ID URI for MCP clients"
  value = local.entra_enabled && local.custom_domain_enabled ? "https://${var.custom_hostname}/mcp" : (
    local.entra_enabled ? "api://mcp-on-azure-${local.environment}-${local.location_short}" : null
  )
}
