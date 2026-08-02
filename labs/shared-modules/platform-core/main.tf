terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

locals {
  # Location short codes for resource naming
  location_short_codes = {
    "polandcentral"  = "plc"
    "eastus"         = "eus"
    "westeurope"     = "weu"
    "northeurope"    = "neu"
    "uksouth"        = "uks"
    "ukwest"         = "ukw"
    "westus"         = "wus"
    "westus2"        = "wus2"
    "westus3"        = "wus3"
    "centralus"      = "cus"
    "southcentralus" = "scus"
    "northcentralus" = "ncus"
    "eastus2"        = "eus2"
    "centralindia"   = "cin"
    "southindia"     = "sin"
    "westindia"      = "win"
  }

  location_short = lookup(local.location_short_codes, var.location, substr(var.location, 0, 3))

  generated_resource_group_name = var.resource_group_name != null ? var.resource_group_name : "rg-${var.workload_name}-${var.environment}-${local.location_short}"
  generated_log_analytics_name  = var.log_analytics_workspace_name != null ? var.log_analytics_workspace_name : "law-${var.workload_name}-${var.environment}-${local.location_short}"
  generated_vnet_name           = "vnet-${var.workload_name}-${var.environment}-${local.location_short}"
  generated_subnet_name         = "snet-${var.workload_name}-${var.environment}-${local.location_short}-001"
  generated_foundry_name        = "cog-${var.workload_name}-${var.environment}-${local.location_short}"
}


# Create resource group
resource "azurerm_resource_group" "rg" {
  name     = local.generated_resource_group_name
  location = var.location
  tags = merge({
    Environment = var.environment
    Workload    = var.workload_name
  }, var.tags)
}

# Create virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = local.generated_vnet_name
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags = merge({
    Environment = var.environment
    Workload    = var.workload_name
  }, var.tags)
}

# Create subnet
resource "azurerm_subnet" "subnet" {
  name                 = local.generated_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.subnet_address_prefixes
}

# Create Log Analytics workspace
resource "azurerm_log_analytics_workspace" "law" {
  name                = local.generated_log_analytics_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_in_days
  tags = merge({
    Environment = var.environment
    Workload    = var.workload_name
  }, var.tags)
}

# Create Application Insights
resource "azurerm_application_insights" "appinsights" {
  name                = "appi-${var.workload_name}-${var.environment}-${local.location_short}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  
  tags = merge({
    Environment = var.environment
    Workload    = var.workload_name
  }, var.tags)
}

# Create Microsoft Foundry Cognitive Account
# Microsoft Foundry uses Cognitive Services with kind = "AIServices"
# Reference: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cognitive_account
resource "azurerm_cognitive_account" "foundry" {
  name                = local.generated_foundry_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "AIServices" # Microsoft Foundry uses AIServices kind

  sku_name = var.foundry_sku

  # Required for networking
  custom_subdomain_name = "${var.workload_name}-${var.environment}-${local.location_short}"

  # Enable outbound network access for AI services
  outbound_network_access_restricted = false

  # Enable public network access for simplicity in labs
  # For production, consider setting this to false and using private endpoints
  public_network_access_enabled = true

  tags = merge({
    Environment = var.environment
    Workload    = var.workload_name
    Foundry     = "true"
  }, var.tags)

  identity {
    type = "SystemAssigned"
  }
}

