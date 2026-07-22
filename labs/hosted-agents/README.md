# Hosted Agents Lab

This lab demonstrates how to deploy infrastructure for **Azure AI Foundry Hosted Agents** using Terraform and GitHub Actions.

## Overview

Azure AI Foundry Hosted Agents provide a managed environment for running AI workloads with built-in security, scaling, and integration with Azure AI services. This lab shows the infrastructure foundation needed to support hosted agents workloads.

## What This Lab Provides

This lab deploys the core platform infrastructure using the shared `platform-core` module:

- **Resource Group** with proper tagging
- **Virtual Network** for network isolation
- **Subnet** for hosting agent resources
- **Log Analytics Workspace** for monitoring
- **Microsoft Foundry Cognitive Account** (kind: AIServices) - the core Foundry resource

## Prerequisites

- Azure subscription
- Azure CLI installed and logged in
- GitHub repository with GitHub Actions enabled

## Quick Start

### 1. Set Up Terraform Backend

Before deploying, set up Azure storage for Terraform state:

```bash
# See detailed guide
# docs/infrastructure/terraform-backend-setup.md
```

### 2. Configure GitHub Secrets

**With OIDC (Recommended):**

Set these secrets in your GitHub repository:

- `ARM_CLIENT_ID` - Azure AD Application ID
- `ARM_SUBSCRIPTION_ID` - Azure Subscription ID
- `ARM_TENANT_ID` - Azure AD Tenant ID
- `TF_STATE_RESOURCE_GROUP` - Terraform state resource group (e.g., `rg-tfstate`)
- `TF_STATE_STORAGE_ACCOUNT` - Terraform state storage account
- `TF_STATE_CONTAINER` - Terraform state container (e.g., `state`)

**With Client Secrets (Alternative):**

Additionally include:
- `ARM_CLIENT_SECRET` - Azure AD Application Secret

### 3. Deploy Infrastructure

**Manual Deployment:**
1. Go to GitHub Actions
2. Run `Terraform Deploy - Hosted Agents` workflow
3. Select environment (dev, staging, prod)
4. Select action (plan, apply, destroy)

**Pull Request:**
- Changes to Terraform files will automatically trigger a `terraform plan`

## Terraform Configuration

The Terraform configuration is in the `terraform/` subdirectory:

```
.
├── terraform/
│   ├── main.tf          # Lab configuration using platform-core module
│   ├── providers.tf     # Terraform providers
│   └── variables.tf     # Environment variables
```

## Module Configuration

The lab uses the shared `platform-core` module:

```hcl
module "platform_core" {
  source = "../../shared-modules/platform-core"
  
  workload_name = "hosted-agents"
  location      = "polandcentral"
  environment   = var.environment
  
  # Network configuration
  vnet_address_space       = ["10.1.0.0/16"]
  subnet_address_prefixes = ["10.1.1.0/24"]
  
  # Monitoring
  log_analytics_sku             = "PerGB2018"
  log_analytics_retention_in_days = 30
  
  # Microsoft Foundry
  foundry_sku = "S0"
}
```

## Outputs

After deployment, the module provides these outputs:

- `resource_group_name` - The created resource group
- `vnet_id` - The virtual network ID
- `subnet_id` - The subnet ID
- `log_analytics_workspace_id` - Log Analytics workspace ID
- `foundry_id` - Microsoft Foundry account ID
- `foundry_name` - Microsoft Foundry account name
- `foundry_endpoint` - Microsoft Foundry endpoint URL

## Cost Optimization

This lab is configured for minimal cost:

- **Log Analytics**: 30-day retention (minimum)
- **Foundry SKU**: S0 (development tier)
- **Location**: Poland Central

For production, consider:
- Log Analytics: 365-day retention
- Foundry SKU: F0 or higher
- Additional monitoring and security features

## Cleanup

To avoid ongoing costs, resources are automatically destroyed daily at 9 PM UTC via the cleanup workflow. You can also manually trigger destruction.

## References

- [Azure AI Foundry Hosted Agents](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents#platform-details)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [Azure Cognitive Services](https://learn.microsoft.com/en-us/azure/cognitive-services/)

## Support

This is a learning lab. For production deployments, review:

- Security configurations
- Network isolation requirements
- Cost management
- Compliance requirements