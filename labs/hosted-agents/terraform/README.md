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

- Set the workload name and environment
- Configure network settings (VNet, subnet)
- Configure Log Analytics settings
- Configure Microsoft Foundry settings
- Define outputs for other modules to consume

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

Defines the input variables for the lab:

- `environment` - Deployment environment (dev, staging, prod)

## Usage

### Local Development

To work with this configuration locally:

```bash
cd labs/hosted-agents/terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan -var="environment=dev"

# Apply the configuration
terraform apply -var="environment=dev"
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
- **Use separate environments** (dev, staging, prod) for different deployment stages
- **Review costs** before deploying to production
- **Clean up resources** when not in use to avoid ongoing costs

## See Also

- [Hosted Agents Lab](../README.md) - Lab overview and quick start
- [Platform Core Module](../../shared-modules/platform-core/README.md) - Shared infrastructure module
- [Terraform Backend Setup](../../../docs/infrastructure/terraform-backend-setup.md) - Backend configuration guide