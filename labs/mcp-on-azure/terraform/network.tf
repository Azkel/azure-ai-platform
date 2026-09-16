# Lab-local core (Foundry-free). Naming matches labs/shared-modules/platform-core
# without pulling Cognitive/Foundry. Extract a thinner shared module later if reused.

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.workload}-${local.environment}-${local.location_short}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${local.workload}-${local.environment}-${local.location_short}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

resource "azurerm_application_insights" "appi" {
  name                = "appi-${local.workload}-${local.environment}-${local.location_short}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.law.id
  tags                = local.common_tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.workload}-${local.environment}-${local.location_short}"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.common_tags
}

# Container Apps Environment — requires /23+ and Microsoft.App/environments delegation
resource "azurerm_subnet" "cae" {
  name                 = "snet-${local.workload}-${local.environment}-${local.location_short}-cae"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.cae_subnet_prefix

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-${local.workload}-${local.environment}-${local.location_short}-pe"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.pe_subnet_prefix
}
