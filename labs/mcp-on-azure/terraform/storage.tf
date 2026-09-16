resource "random_integer" "storage_suffix" {
  min = 1000
  max = 9999
}

locals {
  # st + mcpazure + dev + weu + 4 digits ≈ within 24-char Azure limit
  storage_account_name = "st${local.safe_workload}${local.environment}${local.location_short}${random_integer.storage_suffix.result}"
}

resource "azurerm_storage_account" "demo" {
  name                            = local.storage_account_name
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  # PE + private DNS are the teaching path for the Container App.
  # Keep public access on for lab apply/seed from a laptop; harden to false in prod.
  public_network_access_enabled   = true

  tags = merge(local.common_tags, { Purpose = "mcp-demo" })

  lifecycle {
    precondition {
      condition     = length(local.storage_account_name) >= 3 && length(local.storage_account_name) <= 24
      error_message = "Storage account name '${local.storage_account_name}' must be 3–24 characters."
    }
  }
}

resource "azurerm_storage_container" "demo" {
  name                  = var.storage_blob_container_name
  storage_account_id    = azurerm_storage_account.demo.id
  container_access_type = "private"
}

# MI-only teaching container: user.* must fail here even for subscription Owners
# (Owner is control-plane; blob reads need Storage Blob Data * on this scope).
resource "azurerm_storage_container" "platform_only" {
  name                  = var.storage_platform_only_container_name
  storage_account_id    = azurerm_storage_account.demo.id
  container_access_type = "private"
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "pdnslink-blob-${local.workload}"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-blob-${local.workload}-${local.environment}-${local.location_short}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-blob-${local.workload}"
    private_connection_resource_id = azurerm_storage_account.demo.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

# Operators / demo users — prefer scripts/grant-demo-blob-reader.sh (explicit
# demo-only RBAC). This variable remains for rare IaC-managed readers.
resource "azurerm_role_assignment" "extra_storage_readers" {
  for_each = toset(var.additional_storage_blob_data_reader_principal_ids)

  scope                = azurerm_storage_container.demo.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value
}

# Demo seed blobs (CI/local apply). Requires the applying identity to already have
# Storage Blob Data Contributor (OIDC app: grant at subscription scope — Contributor
# alone cannot self-assign data-plane roles).
resource "azurerm_storage_blob" "hello" {
  name                   = "hello.txt"
  storage_account_name   = azurerm_storage_account.demo.name
  storage_container_name = azurerm_storage_container.demo.name
  type                   = "Block"
  source_content         = "hello from mcp lab\n"
}

resource "azurerm_storage_blob" "platform_only" {
  name                   = "platform-only.txt"
  storage_account_name   = azurerm_storage_account.demo.name
  storage_container_name = azurerm_storage_container.platform_only.name
  type                   = "Block"
  source_content         = "platform identity only — user.* should get 403\n"
}
