# Hosted Agents Lab

This lab demonstrates how to deploy infrastructure for **Azure AI Foundry Hosted Agents** using Terraform and GitHub Actions.

## Overview

Azure AI Foundry Hosted Agents provide a managed environment for running AI workloads with built-in security, scaling, and integration with Azure AI services. This lab shows the infrastructure foundation needed to support hosted agents workloads.

## What This Lab Provides

This lab deploys infrastructure using the shared `platform-core` module plus lab-specific resources:

**Shared Infrastructure (platform-core module):**
- **Resource Group** with proper tagging
- **Virtual Network** for network isolation
- **Subnet** for hosting agent resources
- **Log Analytics Workspace** for monitoring
- **Microsoft Foundry Cognitive Account** (kind: AIServices) - the core Foundry resource
- **Application Insights** for agent observability

**Lab-Specific Resources:**
- **Azure Container Registry** for Docker images
- **Azure Key Vault** for secrets management (using Azure RBAC)
- **Microsoft Foundry Project** for hosting agents

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

After deployment, the Terraform module provides these outputs:

**From platform-core module:**
- `resource_group_name` - The created resource group
- `vnet_id` - The virtual network ID
- `subnet_id` - The subnet ID
- `log_analytics_workspace_id` - Log Analytics workspace ID
- `foundry_id` - Microsoft Foundry account ID
- `foundry_name` - Microsoft Foundry account name
- `foundry_endpoint` - Microsoft Foundry account endpoint URL
- `application_insights_*` - Application Insights resource details

**Lab-specific outputs:**
- `container_registry_*` - Azure Container Registry details
- `key_vault_*` - Azure Key Vault details
- `foundry_project_*` - Microsoft Foundry project details (endpoint, ID, name)

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

## Testing and Validation

After deploying your infrastructure and agent, use these methods to validate your Hosted Agent:

### 1. Deploy the Agent

Run the GitHub Action workflow to build, push, and deploy:
```bash
# Navigate to: Actions > Docker Build, Push and Deploy - Hosted Agents
# Select environment (dev, staging, prod)
# Click "Run workflow"
```

Or use Azure Developer CLI locally:
```bash
# Set the Foundry project endpoint
azd ai project set https://cog-hosted-agents-dev-plc.services.ai.azure.com/api/projects/hosted-agents-project

# Deploy the agent
azd ai agent deploy \
  --name hello-world-dotnet-responses \
  --image acrhostedagentsdevplc.azurecr.io/hello-world-dotnet-responses:latest \
  --protocol responses \
  --protocol-version 2.0.0 \
  --cpu 0.5 \
  --memory 1Gi \
  --set AZURE_AI_MODEL_DEPLOYMENT_NAME=gpt-5.4-mini
```

### 2. Invoke the Agent

**Using Azure CLI:**
```bash
# Get the agent endpoint
azd ai agent show --name hello-world-dotnet-responses --output json

# Invoke the agent
azd ai agent invoke hello-world-dotnet-responses "What is Microsoft Foundry?"
```

**Using curl (direct REST API):**
```bash
# Get access token
TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)

# Get Foundry project endpoint from Terraform outputs
FOUNDRY_ENDPOINT="https://cog-hosted-agents-dev-plc.services.ai.azure.com/api/projects/hosted-agents-project"

# Invoke the agent
curl -X POST "$FOUNDRY_ENDPOINT/agents/hello-world-dotnet-responses/endpoint/protocols/openai/responses?api-version=v1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "input": "What is Microsoft Foundry?",
    "store": true,
    "stream": false
  }'
```

### 3. Monitor with Application Insights

The agent automatically sends telemetry to Application Insights. To view:

1. Go to Azure Portal
2. Navigate to the Application Insights resource: `appi-hosted-agents-dev-plc`
3. Check these sections:
   - **Overview**: Request rate, failure rate, response time
   - **Transaction search**: Individual request traces
   - **Logs**: Full queryable logs
   - **Failures**: Error analysis

**Query examples in Log Analytics:**
```kql
// All agent requests
requests
| where name contains "hello-world-dotnet-responses"
| order by timestamp desc

// Slow requests (> 5 seconds)
requests
| where duration > 5000
| where name contains "hello-world-dotnet-responses"

// Failed requests
requests
| where success == false
| where name contains "hello-world-dotnet-responses"

// Traces from the agent
traces
| where message contains "HelloWorldHandler"
| order by timestamp desc
```

### 4. Check Agent Status

```bash
# List all agents in the project
azd ai agent list

# Show agent details
azd ai agent show --name hello-world-dotnet-responses

# Show agent version status
azd ai agent version list --name hello-world-dotnet-responses

# Stream live logs
azd ai agent monitor --name hello-world-dotnet-responses
```

### 5. Local Testing (Optional)

For quick local validation before deploying to Foundry:

```bash
# Navigate to the sample directory
cd labs/hosted-agents/src/src/hello-world-dotnet-responses

# Restore dependencies
dotnet restore

# Copy .env.example to .env and set required variables
cp .env.example .env
# Edit .env with your Foundry project endpoint and model deployment name

# Run locally
dotnet run

# In another terminal, test with curl
curl -X POST http://localhost:8088/responses \
  -H "Content-Type: application/json" \
  -d '{"input": "Hello local agent!", "stream": false}' | jq
```

## Troubleshooting

### Common Issues

**Agent not responding:**
- Check agent status: `azd ai agent show --name hello-world-dotnet-responses`
- Check version status: Should be `active`
- Check logs: `azd ai agent monitor`

**403 Permission errors:**
- Verify ACR exists and is accessible
- Check role assignments on ACR (AcrPush for deploy, AcrPull for agent identity)
- Run `azd ai agent doctor` for RBAC diagnosis

**Image pull failures:**
- Verify the image tag exists in ACR
- Check agent identity has AcrPull role on ACR
- Use digest-based tags (@sha256:...) for reproducible deploys

**Connection string not injected:**
- Application Insights connection string is auto-injected by Foundry
- The sample code checks for `APPLICATIONINSIGHTS_CONNECTION_STRING`
- If missing, check Foundry project has App Insights configured

## Support

This is a learning lab. For production deployments, review:

- Security configurations
- Network isolation requirements
- Cost management
- Compliance requirements