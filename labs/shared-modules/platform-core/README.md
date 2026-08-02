# Platform Core Module

Shared Terraform module providing core infrastructure components for Azure AI Platform Labs.

## Overview

This module creates the foundational Azure resources needed for hosting AI workloads. It follows Microsoft Cloud Adoption Framework (CAF) naming conventions and is designed to be reused across multiple labs.

## Resources Created

When you use this module, it provisions:

- **Resource Group** - Container for all resources with environment and workload tagging
- **Virtual Network** - Network isolation for your workload
- **Subnet** - Network segment for hosting resources
- **Log Analytics Workspace** - Centralized logging and monitoring
- **Microsoft Foundry Cognitive Account** - Azure AI Foundry capabilities (kind: AIServices)

## Usage

```hcl
module "platform_core" {
  source = "../../shared-modules/platform-core"
  
  # Required
  workload_name = "your-workload"
  location      = "westeurope"
  environment   = "dev"
  
  # Optional - defaults shown
  vnet_address_space       = ["10.0.0.0/16"]
  subnet_address_prefixes = ["10.0.1.0/24"]
  log_analytics_sku        = "PerGB2018"
  log_analytics_retention_in_days = 30
  foundry_sku             = "S0"
  
  # Additional tags
  tags = {
    Project = "MyProject"
    Owner   = "TeamName"
  }
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `workload_name` | string | `"shared"` | No | Workload name for resource naming |
| `resource_group_name` | string | `null` | No | Custom resource group name (auto-generated if not provided) |
| `location` | string | `"westeurope"` | No | Azure region for resources |
| `environment` | string | `"dev"` | No | Environment name (dev, staging, prod) |
| `vnet_address_space` | list(string) | `["10.0.0.0/16"]` | No | Address space for the virtual network |
| `subnet_address_prefixes` | list(string) | `["10.0.1.0/24"]` | No | Address prefixes for the subnet |
| `log_analytics_workspace_name` | string | `null` | No | Custom Log Analytics workspace name (auto-generated if not provided) |
| `log_analytics_sku` | string | `"PerGB2018"` | No | SKU for Log Analytics workspace |
| `log_analytics_retention_in_days` | number | `30` | No | Retention period in days for logs |
| `foundry_sku` | string | `"S0"` | No | SKU for Microsoft Foundry (S0 for labs, F0+ for production) |
| `tags` | map(string) | `{}` | No | Additional tags to apply to all resources |

## Outputs

| Name | Description |
|------|-------------|
| `resource_group_name` | Name of the created resource group |
| `resource_group_location` | Location of the resource group |
| `vnet_id` | ID of the virtual network |
| `vnet_name` | Name of the virtual network |
| `subnet_id` | ID of the subnet |
| `log_analytics_workspace_id` | ID of the Log Analytics workspace |
| `log_analytics_workspace_name` | Name of the Log Analytics workspace |
| `foundry_id` | ID of the Microsoft Foundry account |
| `foundry_name` | Name of the Microsoft Foundry account |
| `foundry_endpoint` | Endpoint URL of the Microsoft Foundry account |
| `foundry_primary_access_key` | Primary access key (sensitive) |
| `foundry_secondary_access_key` | Secondary access key (sensitive) |

## Resource Naming

All resources follow this naming pattern:

```
{resource-type}-{workload}-{environment}-{location-short}
```

Examples:
- Resource Group: `rg-hosted-agents-dev-weu`
- Virtual Network: `vnet-hosted-agents-dev-weu`
- Subnet: `snet-hosted-agents-dev-weu-001`
- Log Analytics: `law-hosted-agents-dev-weu`
- Cognitive Account: `cog-hosted-agents-dev-weu`

Where location short codes include:
- `westeurope` → `weu`
- `polandcentral` → `plc`
- `eastus` → `eus`
- And many others

## Cost Optimization

This module is configured for lab environments with minimal cost:

- Log Analytics retention: 30 days (recommended minimum)
- Foundry SKU: S0 (development tier)
- Standard storage and networking

For production environments, consider:
- Increasing Log Analytics retention to 365 days
- Using Foundry SKU F0 or higher
- Adding additional security and monitoring features

## Dependencies

- Terraform 1.5+
- AzureRM provider ~> 4.0
- Azure CLI for authentication

## See Also

- [Hosted Agents Lab](../hosted-agents/) - Uses this module for Foundry Agent workloads
- [Microsoft Foundry Documentation](https://learn.microsoft.com/en-us/azure/foundry/)
- [Azure Cognitive Services](https://learn.microsoft.com/en-us/azure/cognitive-services/)