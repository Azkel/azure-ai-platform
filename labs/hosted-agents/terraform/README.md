# Terraform Configuration

This directory contains the Terraform configuration for the Hosted Agents lab infrastructure.

## Structure

```
.
├── main.tf          # Primary configuration using platform-core module
├── providers.tf     # Terraform provider configuration
└── variables.tf     # Input variables for the lab
```

## Files

### main.tf

Defines the lab configuration using the shared `platform-core` module. This is where you:

- Set the workload name (environment is hardcoded to `dev`)
- Configure network settings (VNet, subnet)
- Configure Log Analytics settings
- Configure Microsoft Foundry settings
- Provision ACR, Key Vault (incl. agent demo secret), and agent data Storage Account
- Define outputs for other modules / deploy workflows to consume

### providers.tf

Configures the required Terraform providers:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
```

### variables.tf

Defines optional inputs for the lab (SKU overrides, demo secret value, extra RBAC principal IDs). Environment is not a variable — it is hardcoded in `main.tf`.

## Usage

### Local Development

To work with this configuration locally:

```bash
cd labs/hosted-agents/terraform

# Initialize Terraform (configure backend as needed)
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### GitHub Actions

For CI/CD deployments, use the GitHub Actions workflows:

- `.github/workflows/terraform-deploy-hosted-agents.yml` - Deploy with plan/apply/destroy
- `.github/workflows/terraform-cleanup-hosted-agents.yml` - Daily cleanup

### Backend Configuration

The backend is configured via GitHub Actions using Azure Blob Storage. See [Terraform Backend Setup](../../../docs/infrastructure/terraform-backend-setup.md) for details.

## Environment Variables

**With OIDC (Recommended):**

The following environment variables are used by GitHub Actions:

- `ARM_CLIENT_ID` - Azure AD Application ID
- `ARM_SUBSCRIPTION_ID` - Azure Subscription ID
- `ARM_TENANT_ID` - Azure AD Tenant ID
- `TF_STATE_RESOURCE_GROUP` - Resource group for Terraform state
- `TF_STATE_STORAGE_ACCOUNT` - Storage account for Terraform state
- `TF_STATE_CONTAINER` - Container for Terraform state

**With Client Secrets (Alternative):**

Additionally set:
- `ARM_CLIENT_SECRET` - Azure AD Application Secret

## Tips

- **Always run `terraform plan` first** to review changes before applying
- **Clean up resources** when not in use — the daily cleanup workflow helps avoid ongoing costs

## See Also

- [Hosted Agents Lab](../README.md) - Lab overview and quick start
- [Platform Core Module](../../shared-modules/platform-core/README.md) - Shared infrastructure module
- [Terraform Backend Setup](../../../docs/infrastructure/terraform-backend-setup.md) - Backend configuration guide
