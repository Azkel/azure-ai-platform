# Hosted Agents Lab

This lab demonstrates how to deploy infrastructure for **Azure AI Foundry Hosted Agents** using Terraform and GitHub Actions, including a sample HelloWorld agent.

## Overview

Azure AI Foundry Hosted Agents provide a managed environment for running AI workloads with built-in security, scaling, and integration with Azure AI services. This lab provides both the infrastructure foundation and a sample agent to get started quickly.

## Sample: HelloWorld Hosted Agent

This lab includes a **HelloWorld** sample agent that demonstrates:
- **Bring Your Own (BYO)** approach using the **Responses protocol**
- **C#** implementation using `.NET 10` and the `Azure.AI.AgentServer.Responses` SDK
- **Docker** containerization for deployment to Foundry Agent Service
- Integration with **Microsoft Foundry** models via the Responses API

### Sample Location
- **Source code**: `labs/hosted-agents/src/`
- **Main handler**: `src/hello-world-dotnet-responses/Program.cs`
- **Dockerfile**: `src/hello-world-dotnet-responses/Dockerfile`
- **Project file**: `src/hello-world-dotnet-responses/HelloWorld.csproj`

### Sample Features
- Forwards user input to a Foundry model via the Responses API
- Maintains conversation history across turns
- Handles streaming responses with SSE (Server-Sent Events)
- Includes built-in health endpoints (`/readiness`)
- Automatically integrates with Application Insights for telemetry

### What the Sample Does
The HelloWorld agent:
1. Receives a user message via the `/responses` endpoint
2. Retrieves conversation history using `ResponseContext.GetHistoryAsync()`
3. Constructs a prompt with the full conversation context
4. Calls a Foundry model (e.g., `gpt-5-mini`) via the Responses API
5. Returns the model's response to the user

**Required Environment Variables** (auto-injected by Foundry):
- `FOUNDRY_PROJECT_ENDPOINT` - Foundry project endpoint
- `AZURE_AI_MODEL_DEPLOYMENT_NAME` - Model deployment name (default: `gpt-5-mini`)
- `APPLICATIONINSIGHTS_CONNECTION_STRING` - App Insights connection string (auto-injected)

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

### Azure Tools
- **Azure subscription**
- **Azure CLI** installed and logged in
- **Azure Developer CLI (`azd`)** - Required for agent deployment
  - [Installation Guide](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)
  - Verify: `azd --version`
- **GitHub repository** with GitHub Actions enabled

### Development Tools (for local testing)
- **.NET 10 SDK** - Required to build and run the sample locally
  - [Download .NET 10](https://dotnet.microsoft.com/download/dotnet/10.0)
  - Verify: `dotnet --version`
- **Docker** - For local container builds
- **jq** (optional) - For pretty-printing JSON responses

## Region

This lab targets **West Europe** (`westeurope` / `weu`). Hosted Agents data-plane APIs were verified there; Poland Central control-plane deploy can succeed while project/agent APIs return `Project not found`.

## Quick Start

Follow these steps to deploy the infrastructure and sample agent:

### 1. Set Up Terraform Backend

Before deploying, set up Azure storage for Terraform state:

```bash
# See detailed guide
# docs/infrastructure/terraform-backend-setup.md
```

### 2. Configure GitHub Secrets

**With OIDC (Recommended):**

Set these secrets in your GitHub repository Settings > Secrets and variables > Actions:

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
1. Go to GitHub Actions > Workflows
2. Run `Terraform Deploy - Hosted Agents` workflow
3. Select environment (dev, staging, prod)
4. Select action: `plan` (to review changes), then `apply` (to deploy)

**Pull Request:**
- Changes to Terraform files will automatically trigger a `terraform plan` for review

**Important:** The infrastructure (ACR, Foundry account with project management enabled) must be deployed before building and deploying the agent.

**Note:** The Foundry Cognitive Account requires `allowProjectManagement=true` to create projects. This is automatically configured by the updated Terraform configuration. If you have existing infrastructure deployed with older configuration, you may need to:
- Run `terraform apply` again on the updated configuration to enable project management
- Or manually enable it via Azure CLI: `az cognitiveservices account update --name <account> --resource-group <rg> --allow-project-management true`

### 4. Build and Deploy the Sample Agent

After infrastructure is deployed, build and deploy the HelloWorld agent:

1. Run the **Docker Build, Push and Deploy - Hosted Agents** workflow
2. Select the same environment as your infrastructure
3. The workflow will:
   - Build the Docker image from the sample source
   - Push it to Azure Container Registry
   - Deploy it to Microsoft Foundry

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
  location      = "westeurope"
  environment   = var.environment

  # Network configuration (172.16/16; required in regions without Class A / 10.x for Agent Service)
  vnet_address_space      = ["172.16.0.0/16"]
  subnet_address_prefixes = ["172.16.1.0/24"]

  # Monitoring
  log_analytics_sku               = "PerGB2018"
  log_analytics_retention_in_days = 30

  # Microsoft Foundry + Hosted Agents network injection at account create
  foundry_sku                             = "S0"
  foundry_agent_network_injection_enabled = true
}
```

## CI/CD Pipeline

This lab uses **GitHub Actions** for enterprise-scale CI/CD with dedicated runners (not local developer machines).

### Build Pipeline

The sample is built using the **[Docker Build, Push and Deploy - Hosted Agents](../../.github/workflows/docker-build-push-hosted-agents.yml)** workflow:

**Workflow file**: `.github/workflows/docker-build-push-hosted-agents.yml`

**What it does:**
1. **Validates infrastructure** - Checks that ACR and Foundry project exist (must be deployed first via Terraform)
2. **Builds Docker image** - Uses `docker/build-push-action` to build the agent image from `labs/hosted-agents/src/src/hello-world-dotnet-responses/Dockerfile`
3. **Pushes to ACR** - Tags and pushes the image to Azure Container Registry with multiple tags (branch, tag, sha, latest)
4. **Deploys to Foundry** - Uses `azd ai agent deploy` to deploy the agent to the Foundry project

**Build options:**
- **Full pipeline**: Builds, pushes, and deploys the agent
- **Build only**: `skip-deploy: true` - Builds and pushes without deploying
- **Deploy only**: `deploy-only: true` - Deploys an existing image (uses `latest` tag)

**Naming convention:**
- ACR name: `acr{workload_no_hyphens}{environment}{location_short}` (e.g., `acrhostedagentsdevweu`)
- Agent name: `hello-world-dotnet-responses`
- Image: `{ACR}.azurecr.io/hello-world-dotnet-responses:{tag}`

**References:**
- [Set up CI/CD with Azure Developer CLI](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/set-up-ci-cd-cli)
- [Deploy from private ACR](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry)

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

**Important Note on Resource Deletion:**
- **Immediately deleted**: Resource Group, VNet, Subnet
- **7-day soft delete retention (auto-purged after 7 days)**:
  - **Microsoft Foundry Cognitive Account**: Azure enforces a mandatory 7-day soft delete retention that cannot be disabled. After `terraform destroy`, the account will be in soft-delete state for 7 days before automatic purge.
  - **Azure Key Vault**: Has a minimum 7-day soft delete retention (Azure requirement) with `purge_protection_enabled = false`, allowing automatic purge after 7 days.
  - **Azure Container Registry (ACR)**: Has soft delete enabled by default with minimum 7-day retention, auto-purged after the retention period.
  - **Application Insights**: Has Smart Detection rules that can block deletion. Terraform configuration attempts to disable this, but if issues occur:
- **To purge immediately** (bypassing the 7-day wait):
  ```bash
  # Purge Cognitive Services / Foundry account
  az cognitiveservices account purge --name cog-{workload}-{environment}-{location} --resource-group rg-{workload}-{environment}-{location} --location {location}
  
  # Purge Key Vault
  az keyvault purge --name kv-{workload}-{environment}-{location-short} --location {location}
  
  # Purge ACR (if needed)
  az acr purge --name acr{workload}{environment}{location-short} --registry acr{workload}{environment}{location-short}.azurecr.io
  
  # Delete Application Insights Smart Detection rules (if blocking deletion)
  az monitor app-insights smart-detection list --resource-group rg-{workload}-{environment}-{location-short} --app appi-{workload}-{environment}-{location-short} | jq -r '.[] | .name' | xargs -I {} az monitor app-insights smart-detection delete --resource-group rg-{workload}-{environment}-{location-short} --app appi-{workload}-{environment}-{location-short} --name {}
  ```
- Consider adding a post-destroy cleanup step in your workflow to purge soft-deleted resources

## References

### Microsoft Foundry
- [Azure AI Foundry Hosted Agents](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents#platform-details)
- [Hosted Agents Overview](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents)
- [Deploy Hosted Agent from Private ACR](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry)
- [Set up CI/CD with Azure Developer CLI](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/set-up-ci-cd-cli)

### Azure Developer CLI
- [Install Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)
- [Azure Developer CLI Documentation](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/)

### Infrastructure as Code
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [Azure Cognitive Services](https://learn.microsoft.com/en-us/azure/cognitive-services/)

### .NET Development
- [.NET 10 Download](https://dotnet.microsoft.com/download/dotnet/10.0)
- [Azure.AI.AgentServer.Responses SDK](https://www.nuget.org/packages/Azure.AI.AgentServer.Responses)

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
azd ai project set https://hosted-agents-dev-weu.services.ai.azure.com/api/projects/hosted-agents-project

# Deploy the agent (from labs/hosted-agents/src with azure.yaml image/env configured)
azd deploy hello-world-dotnet-responses --from-package acrhostedagentsdevweu.azurecr.io/hello-world-dotnet-responses:latest --no-prompt
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
FOUNDRY_ENDPOINT="https://hosted-agents-dev-weu.services.ai.azure.com/api/projects/hosted-agents-project"

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
2. Navigate to the Application Insights resource: `appi-hosted-agents-dev-weu`
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