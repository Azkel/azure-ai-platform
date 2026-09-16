# Optional custom domain (e.g. mcp.azure.smyk.it) on an existing public DNS zone.
# Records live in the shared zone RG; the Container App stays in the lab RG.

locals {
  custom_domain_enabled = var.custom_hostname != "" && var.dns_zone_name != "" && var.dns_zone_resource_group_name != ""
  # hostname "mcp.azure.smyk.it" in zone "azure.smyk.it" → relative label "mcp"
  custom_domain_relative = local.custom_domain_enabled ? trimsuffix(var.custom_hostname, ".${var.dns_zone_name}") : ""
}

data "azurerm_dns_zone" "shared" {
  count               = local.custom_domain_enabled ? 1 : 0
  name                = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group_name
}

resource "azurerm_dns_txt_record" "mcp_asuid" {
  count               = local.custom_domain_enabled ? 1 : 0
  name                = "asuid.${local.custom_domain_relative}"
  zone_name           = data.azurerm_dns_zone.shared[0].name
  resource_group_name = data.azurerm_dns_zone.shared[0].resource_group_name
  ttl                 = 300

  record {
    value = azurerm_container_app.mcp.custom_domain_verification_id
  }
}

resource "azurerm_dns_cname_record" "mcp" {
  count               = local.custom_domain_enabled ? 1 : 0
  name                = local.custom_domain_relative
  zone_name           = data.azurerm_dns_zone.shared[0].name
  resource_group_name = data.azurerm_dns_zone.shared[0].resource_group_name
  ttl                 = 300
  record              = azurerm_container_app.mcp.ingress[0].fqdn
}

# Managed certificate binding — Azure often creates the hostname with
# bindingType=Disabled first. After DNS propagates, run:
#   ./scripts/bind-custom-domain.sh
# (or az containerapp hostname bind …) so TLS becomes SniEnabled.
resource "azurerm_container_app_custom_domain" "mcp" {
  count          = local.custom_domain_enabled ? 1 : 0
  name           = var.custom_hostname
  container_app_id = azurerm_container_app.mcp.id

  depends_on = [
    azurerm_dns_txt_record.mcp_asuid,
    azurerm_dns_cname_record.mcp,
  ]

  lifecycle {
    ignore_changes = [
      certificate_binding_type,
      container_app_environment_certificate_id,
    ]
  }
}
