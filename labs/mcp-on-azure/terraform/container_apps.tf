resource "azurerm_container_registry" "acr" {
  name                = "acr${local.safe_workload}${local.environment}${local.location_short}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = local.common_tags
}

resource "azurerm_container_app_environment" "cae" {
  name                       = "cae-${local.workload}-${local.environment}-${local.location_short}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  # VNet injection is the Acceler8it path; optional fallback if the region fails ManagedCluster init.
  infrastructure_subnet_id       = var.container_apps_vnet_injection ? azurerm_subnet.cae.id : null
  internal_load_balancer_enabled = false
  tags                           = local.common_tags

  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }
}

locals {
  use_acr_image = var.mcp_image != "" && startswith(var.mcp_image, azurerm_container_registry.acr.login_server)
}

resource "azurerm_container_app" "mcp" {
  name                         = "ca-mcp-${local.environment}-${local.location_short}"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  tags                         = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  dynamic "registry" {
    for_each = local.use_acr_image ? [1] : []
    content {
      server   = azurerm_container_registry.acr.login_server
      identity = "System"
    }
  }

  dynamic "secret" {
    for_each = local.entra_enabled ? [1] : []
    content {
      name  = "microsoft-provider-authentication-secret"
      value = azuread_application_password.mcp[0].value
    }
  }

  template {
    min_replicas = local.custom_domain_enabled || local.entra_enabled ? 1 : 0
    max_replicas = 3

    container {
      name   = "mcp"
      image  = local.mcp_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "AZURE_STORAGE_ACCOUNT_NAME"
        value = azurerm_storage_account.demo.name
      }
      env {
        name  = "AZURE_STORAGE_CONTAINER_NAME"
        value = azurerm_storage_container.demo.name
      }
      env {
        name  = "AZURE_STORAGE_PLATFORM_ONLY_CONTAINER_NAME"
        value = azurerm_storage_container.platform_only.name
      }
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.appi.connection_string
      }
      env {
        name  = "ASPNETCORE_URLS"
        value = "http://+:8080"
      }

      dynamic "env" {
        for_each = local.custom_domain_enabled ? [1] : []
        content {
          name  = "MCP_PUBLIC_BASE_URL"
          value = "https://${var.custom_hostname}"
        }
      }
      dynamic "env" {
        for_each = local.entra_enabled ? [1] : []
        content {
          name = "MCP_ENTRA_SCOPE"
          # Prefer HTTPS resource scope for MCP OAuth; falls back to api:// when no custom domain.
          value = local.custom_domain_enabled ? "https://${var.custom_hostname}/mcp/access_as_user" : "api://mcp-on-azure-${local.environment}-${local.location_short}/access_as_user"
        }
      }
      dynamic "env" {
        for_each = local.entra_enabled && local.custom_domain_enabled ? [1] : []
        content {
          name  = "MCP_ENTRA_RESOURCE"
          value = "https://${var.custom_hostname}/mcp"
        }
      }
      dynamic "env" {
        for_each = local.entra_enabled ? [1] : []
        content {
          name  = "MCP_ENTRA_API_URI"
          value = "api://mcp-on-azure-${local.environment}-${local.location_short}"
        }
      }

      dynamic "env" {
        for_each = local.entra_enabled ? [1] : []
        content {
          name  = "MCP_ENTRA_TENANT_ID"
          value = data.azurerm_client_config.current.tenant_id
        }
      }
      dynamic "env" {
        for_each = local.entra_enabled ? [1] : []
        content {
          name  = "MCP_ENTRA_CLIENT_ID"
          value = azuread_application.mcp[0].client_id
        }
      }
      dynamic "env" {
        for_each = local.entra_enabled ? [1] : []
        content {
          name        = "MCP_ENTRA_CLIENT_SECRET"
          secret_name = "microsoft-provider-authentication-secret"
        }
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [azurerm_private_endpoint.blob]
}

resource "azurerm_role_assignment" "mcp_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.mcp.identity[0].principal_id
}

resource "azurerm_role_assignment" "mcp_storage_reader" {
  scope                = azurerm_storage_account.demo.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_container_app.mcp.identity[0].principal_id
}
