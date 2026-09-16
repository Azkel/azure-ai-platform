# GitHub OIDC Setup Guide for Azure Authentication

This guide explains how to configure GitHub OIDC authentication for Azure deployments in the Azure AI Platform Labs. GitHub OIDC (OpenID Connect) allows workflows to authenticate with Azure using short-lived tokens, eliminating the need for long-lived secrets and following security best practices.

## Overview

GitHub OIDC authentication provides:

- **No Long-lived Secrets**: Uses short-lived tokens instead of static credentials
- **Improved Security**: Tokens have limited lifespan and scope
- **Better Audit Trails**: Enhanced tracking and monitoring of deployments
- **Best Practices**: Follows modern cloud security standards

## Prerequisites

- Azure account with contributor permissions
- Azure CLI installed and logged in
- GitHub repository with workflows that need Azure authentication
- Administrative access to your Azure AD tenant

## Setup Instructions

### Step 1: Create Azure AD Application

Create an application registration in your Azure AD tenant:

```bash
# Connect to Azure and set your subscription
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Create AD application for GitHub Actions
az ad app create --display-name "GitHubActions-AzureAILabs"
# Note the appId from the output - this is your ARM_CLIENT_ID

# Get your tenant ID
az account show --query tenantId --output tsv
```

### Step 2: Configure Federated Credentials

Configure a federated credential for your GitHub repository environment:

```bash
# Set your repository and environment details
REPO="your-org/your-repo"
ENVIRONMENT="labs"
APP_ID="YOUR_APP_ID_FROM_STEP_1"

# Create federated credential
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{\"name\":\"GitHub-OIDC-$ENVIRONMENT\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"repo:$REPO:environment:$ENVIRONMENT\",\"audiences\":[\"api://AzureADTokenExchange\"],\"description\":\"GitHub OIDC for Azure AI Labs $ENVIRONMENT environment\"}"
```

### Step 3: Assign Azure RBAC Roles

Assign the necessary permissions to your application's service principal:

```bash
# Get the service principal ID
SERVICE_PRINCIPAL_ID=$(az ad sp list --display-name "GitHubActions-AzureAILabs" --query "[0].id" --output tsv)

# Assign Contributor role at subscription level
az role assignment create \
  --assignee "$SERVICE_PRINCIPAL_ID" \
  --role "Contributor" \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID"

# For Terraform state management, assign Storage Blob Data Contributor
# Replace with your own storage account name
STORAGE_ACCOUNT="ai0labs0pl"  # Or your chosen name
az role assignment create \
  --assignee "$SERVICE_PRINCIPAL_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/rg-tfstate/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"
```

### Step 3b: Microsoft Graph app roles (MCP on Azure)

The MCP lab Terraform manages Entra app registrations and delegated grants. The OIDC app needs these **application** permissions on Microsoft Graph (admin consent / app role assignments), not only Azure RBAC:

| Permission | Why |
|---|---|
| `Application.ReadWrite.All` | Create/update/delete the lab app registration |
| `Directory.Read.All` | Resolve first-party service principals (Graph, Storage) |
| `DelegatedPermissionGrant.ReadWrite.All` | Grant User.Read + Storage `user_impersonation` for OBO |

```bash
APP_ID="YOUR_APP_ID_FROM_STEP_1"
SP_OID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
GRAPH_SP=$(az ad sp show --id 00000003-0000-0000-c000-000000000000 --query id -o tsv)
APP_OID=$(az ad app show --id "$APP_ID" --query id -o tsv)

# Declare required resource access on the app
az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$APP_OID" \
  --headers "Content-Type=application/json" \
  --body '{"requiredResourceAccess":[{"resourceAppId":"00000003-0000-0000-c000-000000000000","resourceAccess":[
    {"id":"e1fe6dd8-ba31-4d61-89e7-88639da4683d","type":"Scope"},
    {"id":"1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9","type":"Role"},
    {"id":"7ab1d382-f21e-4acd-a863-ba3e13f7da61","type":"Role"},
    {"id":"8e8e4742-1d95-4f68-9d56-6ee75648c72a","type":"Role"}
  ]}]}'

# Assign the application roles (tenant admin consent equivalent for Roles)
for ROLE in \
  1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9 \
  7ab1d382-f21e-4acd-a863-ba3e13f7da61 \
  8e8e4742-1d95-4f68-9d56-6ee75648c72a
do
  az rest --method POST \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OID/appRoleAssignments" \
    --headers "Content-Type=application/json" \
    --body "{\"principalId\":\"$SP_OID\",\"resourceId\":\"$GRAPH_SP\",\"appRoleId\":\"$ROLE\"}"
done
```

### Step 3c: Storage data-plane + role assignment rights (MCP on Azure)

Azure **Contributor** cannot grant itself `Storage Blob Data *` roles. The OIDC app needs these Azure RBAC assignments (subscription or lab RG scope) so GitHub Actions can seed demo blobs and manage data-plane role assignments:

| Role | Why |
|---|---|
| `Storage Blob Data Contributor` | Upload `hello.txt` / `platform-only.txt` (workflow seed or `azurerm_storage_blob`) |
| `User Access Administrator` | Create `azurerm_role_assignment` resources (MI reader, extra demo readers) |

```bash
APP_ID="YOUR_APP_ID_FROM_STEP_1"
SP_OID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
SUB=$(az account show --query id -o tsv)

az role assignment create --assignee-object-id "$SP_OID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "/subscriptions/$SUB"

az role assignment create --assignee-object-id "$SP_OID" --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" --scope "/subscriptions/$SUB"
```

Without `Storage Blob Data Contributor`, seed fails with “You do not have the required permissions… Storage Blob Data Contributor” even though control-plane apply succeeded.

### Step 4: Configure GitHub Secrets

Add these secrets to your GitHub repository:

```bash
# Using GitHub CLI
gh secret set ARM_CLIENT_ID --body "YOUR_APP_ID"
gh secret set ARM_SUBSCRIPTION_ID --body "YOUR_SUBSCRIPTION_ID"
gh secret set ARM_TENANT_ID --body "YOUR_TENANT_ID"

# If using separate storage for Terraform state
# Use generic names or replace with your own
gh secret set TF_STATE_RESOURCE_GROUP --body "rg-tfstate"
gh secret set TF_STATE_STORAGE_ACCOUNT --body "ai0labs0pl"  # Use your own unique name
gh secret set TF_STATE_CONTAINER --body "state"
```

Or manually in GitHub:
- Go to Settings → Secrets → Actions
- Add `ARM_CLIENT_ID`, `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID`
- Add Terraform state secrets if applicable

## GitHub Actions Workflow Configuration

Update your workflow to use OIDC authentication:

```yaml
- name: Configure Azure CLI with OIDC
  uses: azure/login@v1
  with:
    client-id: ${{ secrets.ARM_CLIENT_ID }}
    tenant-id: ${{ secrets.ARM_TENANT_ID }}
    subscription-id: ${{ secrets.ARM_SUBSCRIPTION_ID }}
    enable-OIDC: true
    environment: ${{ github.event.inputs.environment || 'dev' }}
```

## Verification

### Test OIDC Authentication

1. Run a test workflow:
   ```bash
   gh workflow run terraform-deploy-hosted-agents.yml -f environment=dev -f action=plan
   ```

2. Check the workflow logs:
   - The Azure login step should show successful OIDC authentication
   - No client secrets should be referenced

3. Verify in Azure Portal:
   - Navigate to Azure Active Directory → App registrations → Your app
   - Check "Sign-in logs" to see OIDC token usage from GitHub Actions

## Troubleshooting

### Common Issues

**OIDC token rejected**
- Verify federated credential subject matches exactly: `repo:ORG/REPO:environment:ENV_NAME`
- Check that the Azure AD app has API permissions for Azure Service Management
- Ensure the environment name in GitHub matches the federated credential

**Insufficient permissions**
- Verify the service principal has the required RBAC roles
- Check role assignments at both subscription and resource group levels
- Review Azure AD sign-in logs for the service principal

**Workflow hangs at Azure login**
- Verify GitHub environment exists and matches the federated credential
- Check that all required secrets are correctly configured
- Ensure the Azure AD app registration is in the same tenant as your subscription

### Debugging Commands

```bash
# Check Azure AD app registration
az ad app show --id YOUR_APP_ID

# List federated credentials
az ad app federated-credential list --id YOUR_APP_ID

# Verify service principal
az ad sp show --id YOUR_APP_ID

# Check role assignments
az role assignment list --assignee YOUR_SERVICE_PRINCIPAL_ID --include-inherited
```

## Security Best Practices

### Least Privilege
- Assign only the minimum required permissions
- Use custom roles instead of built-in roles when possible
- Regularly review and audit permissions

### Environment Isolation
- Use separate Azure AD applications for different environments
- Configure different GitHub environments (dev, staging, prod)
- Apply appropriate RBAC roles based on environment sensitivity

### Monitoring
- Set up alerts for unusual OIDC token usage patterns
- Monitor Azure AD sign-in logs for the service principal
- Review GitHub Actions workflow runs regularly

## References

- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Azure OIDC with GitHub Actions](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure?tabs=azure-cli%2Cwindows#use-the-azure-login-action-with-openid-connect)
- [Azure AD Federated Credentials](https://learn.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation)

## Support

For issues with OIDC setup:

1. **GitHub Status**: [https://www.githubstatus.com/](https://www.githubstatus.com/)
2. **Azure Status**: [https://status.azure.com/](https://status.azure.com/)
3. **GitHub Community**: [https://github.com/orgs/community/discussions](https://github.com/orgs/community/discussions)
4. **Azure Support**: [https://azure.microsoft.com/en-us/support/](https://azure.microsoft.com/en-us/support/)