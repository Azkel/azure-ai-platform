# Terraform Backend Setup Guide

This guide explains how to set up Azure Blob Storage as a remote backend for Terraform state storage for the Azure AI Platform Labs.

## Overview

Using a remote backend provides several benefits:

- **State Sharing**: Multiple team members can access the same Terraform state
- **State Locking**: Prevents concurrent modifications that could corrupt state
- **Centralized Management**: State files are stored in a known, accessible location
- **Security**: State can be protected with Azure RBAC and storage account security

## Authentication Method

✅ **This setup uses Azure AD authentication (recommended)**

The GitHub Actions workflows authenticate using Azure AD service principals via the `azure/login` action. The Terraform `azurerm` backend will automatically use these credentials. **Access Keys are NOT required or used**, which means your storage account can (and should) disable access key authentication.

## Quick Start (Azure CLI)

The GitHub Actions workflows expect the following configuration by default:
- Resource Group: `rg-tfstate`
- Storage Account: `ai0labs0pl` (must be globally unique - use your own name)
- Container: `state`
- Subscription: `YOUR_SUBSCRIPTION_ID`

### 1. Create Resource Group
```bash
az group create --name rg-tfstate --location polandcentral
```

### 2. Create Storage Account with Azure AD Authentication Only
**Important**: The storage account name must be globally unique.
**Note**: Use your own unique name instead of the examples below.

```bash
# Set your storage account name (must be globally unique)
STORAGE_ACCOUNT="ai0labs0pl"

az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group rg-tfstate \
  --location polandcentral \
  --sku Standard_LRS \
  --encryption-services blob \
  --https-only true \
  --allow-blob-public-access false \
  --key-policy "key-expiry=P30D"  # Rotate keys every 30 days if enabled
```

### 3. Disable Access Keys (Recommended for Security)
```bash
# Disable storage account keys for Azure AD-only authentication
az storage account update \
  --name "$STORAGE_ACCOUNT" \
  --resource-group rg-tfstate \
  --enable-blob-encrypt-service true \
  --key-policy "key-expiry=P1D,key-auto-rotation=false"  # Effectively disables keys
```

### 4. Create Blob Container
```bash
az storage container create \
  --name state \
  --account-name "$STORAGE_ACCOUNT" \
  --public-access off \
  --auth-mode login  # Use Azure AD authentication
```

### 5. Assign RBAC Roles for GitHub Actions
The service principal used by GitHub Actions needs **Storage Blob Data Contributor** role:

```bash
# Get your service principal ID (from your GitHub ARM_CLIENT_ID secret)
SERVICE_PRINCIPAL_ID=$(az ad sp show --id YOUR_APPLICATION_ID --query id --output tsv)

# Assign required role
az role assignment create \
  --assignee "$SERVICE_PRINCIPAL_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/rg-tfstate/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"
```

## GitHub Actions Configuration

**With OIDC (Recommended):**
Set these secrets in your GitHub repository:
- `ARM_CLIENT_ID` - Azure AD Application (client) ID
- `ARM_SUBSCRIPTION_ID` - Azure Subscription ID
- `ARM_TENANT_ID` - Azure AD Tenant ID
- `TF_STATE_RESOURCE_GROUP=rg-tfstate`
- `TF_STATE_STORAGE_ACCOUNT=ai0labs0pl` (use your own unique name)
- `TF_STATE_CONTAINER=state`

**With Client Secrets (Alternative):**
Additionally set:
- `ARM_CLIENT_SECRET` - Azure AD Application client secret

## Troubleshooting

### Azure AD Authentication Issues

**Error: "Authentication Failed" or "Access Denied"**
- Verify the service principal has **Storage Blob Data Contributor** role on the storage account
- Check that the role assignment scope is correct (storage account level, not just resource group)
- Ensure the service principal hasn't expired or been disabled

**Error: "Storage account does not support access key authentication"**
This is expected and correct! The setup uses Azure AD authentication, not access keys.
- Verify your GitHub Actions workflow uses `azure/login` before `terraform init`
- Check that `ARM_*` environment variables are properly set as GitHub secrets
- Ensure the storage account allows Azure AD authentication

### Storage Account Configuration Issues

**Verify Azure AD authentication is enabled:**
```bash
az storage account show \
  --name "$STORAGE_ACCOUNT" \
  --resource-group rg-tfstate \
  --query "[enableAzureADAuthorization, keyCreationTime, keyPolicy]"
```

**Check RBAC assignments:**
```bash
az role assignment list \
  --assignee YOUR_SERVICE_PRINCIPAL_ID \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/rg-tfstate/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
  --include-inherited \
  --query "[].roleDefinitionName"
```

### Terraform Backend Configuration

**Verify backend configuration in workflow:**
The GitHub Actions workflows pass backend configuration via command line:
```yaml
- backend-config="resource_group_name=$TF_STATE_RESOURCE_GROUP"
- backend-config="storage_account_name=$TF_STATE_STORAGE_ACCOUNT"
- backend-config="container_name=$TF_STATE_CONTAINER"
- backend-config="key=$TF_STATE_KEY"
```

These are automatically resolved from GitHub secrets and do NOT require access keys.

## Azure AD Best Practices

### Principle of Least Privilege
- Assign only **Storage Blob Data Contributor** role (not Owner or Contributor)
- Scope the role assignment to the storage account only
- Use separate service principals for different environments

### Security Hardening
- Enable **Storage Service Encryption** (enabled by default with `--encryption-services blob`)
- Disable **public network access** (`--allow-blob-public-access false`)
- Enable **HTTPS-only access** (`--https-only true`)
- Consider adding **firewall rules** to restrict access to known IP ranges

### Monitoring
- Enable **Storage Analytics logs** for audit trail
- Set up alerts for **unusual access patterns**
- Monitor **Azure AD sign-in logs** for the service principal

## References
- [Azure Terraform Backend](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/backends/azurerm)
- [GitHub OIDC Setup](../github/github-oidc-setup.md) - For passwordless authentication
- [Azure Storage Authentication](https://learn.microsoft.com/en-us/azure/storage/common/authenticate-passwordless-access)
- [Terraform Azure AD Authentication](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret)