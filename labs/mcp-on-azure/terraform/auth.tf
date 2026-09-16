# Container Apps Easy Auth (Microsoft Entra) via authConfigs.

resource "azapi_resource" "mcp_auth" {
  count     = local.entra_enabled ? 1 : 0
  type      = "Microsoft.App/containerApps/authConfigs@2024-03-01"
  name      = "current"
  parent_id = azurerm_container_app.mcp.id

  body = {
    properties = {
      platform = {
        enabled = true
      }
      globalValidation = {
        # AllowAnonymous so unauthenticated /mcp reaches the app and can return
        # RFC 9728 WWW-Authenticate (ACA Easy Auth Return401 does not emit PRM).
        unauthenticatedClientAction = "AllowAnonymous"
        excludedPaths = [
          "/",
          "/health",
          "/config.json",
          "/.well-known/oauth-protected-resource",
          "/.well-known/oauth-protected-resource/mcp",
        ]
      }
      identityProviders = {
        azureActiveDirectory = {
          enabled = true
          registration = {
            clientId                = azuread_application.mcp[0].client_id
            clientSecretSettingName = "microsoft-provider-authentication-secret"
            openIdIssuer            = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/v2.0"
          }
          validation = {
            allowedAudiences = compact([
              azuread_application.mcp[0].client_id,
              "api://mcp-on-azure-${local.environment}-${local.location_short}",
              local.custom_domain_enabled ? "https://${var.custom_hostname}" : null,
              local.custom_domain_enabled ? "https://${var.custom_hostname}/mcp" : null,
            ])
          }
        }
      }
      login = {
        tokenStore = {
          enabled = false
        }
      }
      httpSettings = {
        requireHttps = true
      }
    }
  }

  depends_on = [
    azurerm_container_app.mcp,
    azuread_application_password.mcp,
  ]
}
