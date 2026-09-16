# Microsoft Entra app registration for Container Apps Easy Auth + OBO to Storage.

locals {
  entra_enabled = var.enable_entra_auth
  # Prefer custom domain callback; default CA FQDN can be added in the portal if needed.
  entra_redirect_uris = local.entra_enabled ? compact([
    local.custom_domain_enabled ? "https://${var.custom_hostname}/.auth/login/aad/callback" : null,
  ]) : []
}

resource "random_uuid" "mcp_scope" {
  count = local.entra_enabled ? 1 : 0
}

data "azuread_application_published_app_ids" "well_known" {
  count = local.entra_enabled ? 1 : 0
}

data "azuread_service_principal" "msgraph" {
  count     = local.entra_enabled ? 1 : 0
  client_id = data.azuread_application_published_app_ids.well_known[0].result["MicrosoftGraph"]
}

# Azure Storage first-party app (delegated user_impersonation for OBO).
data "azuread_service_principal" "storage" {
  count     = local.entra_enabled ? 1 : 0
  client_id = "e406a681-f3d4-42a8-90b6-c2b029497af1"
}

resource "azuread_application" "mcp" {
  count            = local.entra_enabled ? 1 : 0
  display_name     = "mcp-on-azure-${local.environment}"
  sign_in_audience = "AzureADMyOrg"

  identifier_uris = compact([
    "api://mcp-on-azure-${local.environment}-${local.location_short}",
    local.custom_domain_enabled ? "https://${var.custom_hostname}" : null,
    local.custom_domain_enabled ? "https://${var.custom_hostname}/mcp" : null,
  ])

  web {
    redirect_uris = length(local.entra_redirect_uris) > 0 ? local.entra_redirect_uris : null
    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = true
    }
  }

  api {
    mapped_claims_enabled          = true
    requested_access_token_version = 2

    oauth2_permission_scope {
      admin_consent_description  = "Allow the app to access the MCP server on behalf of the signed-in user."
      admin_consent_display_name = "Access MCP on Azure"
      enabled                    = true
      id                         = random_uuid.mcp_scope[0].result
      type                       = "User"
      user_consent_description   = "Allow the app to access the MCP server on your behalf."
      user_consent_display_name  = "Access MCP on Azure"
      value                      = "access_as_user"
    }
  }

  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.well_known[0].result["MicrosoftGraph"]

    resource_access {
      id   = data.azuread_service_principal.msgraph[0].oauth2_permission_scope_ids["User.Read"]
      type = "Scope"
    }
  }

  required_resource_access {
    resource_app_id = data.azuread_service_principal.storage[0].client_id

    resource_access {
      id   = data.azuread_service_principal.storage[0].oauth2_permission_scope_ids["user_impersonation"]
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "mcp" {
  count     = local.entra_enabled ? 1 : 0
  client_id = azuread_application.mcp[0].client_id
}

resource "azuread_application_password" "mcp" {
  count          = local.entra_enabled ? 1 : 0
  application_id = azuread_application.mcp[0].id
  display_name   = "cae-easy-auth"

  lifecycle {
    ignore_changes = [end_date]
  }
}

resource "azuread_service_principal_delegated_permission_grant" "graph" {
  count                                = local.entra_enabled ? 1 : 0
  service_principal_object_id          = azuread_service_principal.mcp[0].object_id
  resource_service_principal_object_id = data.azuread_service_principal.msgraph[0].object_id
  claim_values                         = ["User.Read"]
}

resource "azuread_service_principal_delegated_permission_grant" "storage" {
  count                                = local.entra_enabled ? 1 : 0
  service_principal_object_id          = azuread_service_principal.mcp[0].object_id
  resource_service_principal_object_id = data.azuread_service_principal.storage[0].object_id
  claim_values                         = ["user_impersonation"]
}

# Allow Azure CLI to request the MCP API scope (lab smoke / demos).
resource "azuread_application_pre_authorized" "azure_cli" {
  count                = local.entra_enabled ? 1 : 0
  application_id       = azuread_application.mcp[0].id
  authorized_client_id = "04b07795-8ddb-461a-bbee-02f9e1bf7b46" # Azure CLI
  permission_ids       = [random_uuid.mcp_scope[0].result]
}

# VS Code MCP / Microsoft authentication broker (interactive OAuth).
resource "azuread_application_pre_authorized" "vscode" {
  count                = local.entra_enabled ? 1 : 0
  application_id       = azuread_application.mcp[0].id
  authorized_client_id = "aebc6443-996d-45c2-90f0-388ff96faa56" # Visual Studio Code
  permission_ids       = [random_uuid.mcp_scope[0].result]
}
