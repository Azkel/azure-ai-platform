# Azure AI Platform Labs - Documentation

This directory contains **global documentation** for setting up and using the Azure AI Platform Labs infrastructure. Each lab also includes its own dedicated README with lab-specific information.

## 📁 Documentation Structure

### Global Documentation (this directory)
```
docs/
├── README.md
├── adrs/                              # Architecture Decision Records
├── github/
│   └── github-oidc-setup.md
└── infrastructure/
    └── terraform-backend-setup.md
```

### Architecture decisions

→ [ADRs index](./adrs/README.md) (OIDC/state, module strategy, MI/OBO, PE, MCP ingress, ...)

### Lab-Specific Documentation
Each lab has its own documentation:
- [Hosted Agents Lab](../../labs/hosted-agents/README.md) - Lab overview and usage
- [MCP on Azure](../../labs/mcp-on-azure/README.md) - Short start + `docs/` detail pages
- [Platform Core Module](../../labs/shared-modules/platform-core/README.md) - Shared module documentation

See the [main README](../../README.md) for a complete list of all labs.

## 🚀 Quick Start

### 1. Set Up Terraform Backend

Before running any GitHub Actions workflows, you need to set up Azure storage for Terraform state:

→ [Terraform Backend Setup](./infrastructure/terraform-backend-setup.md)

This guide provides:
- Azure CLI commands to create the required storage account
- GitHub Secrets configuration
- Best practices for state management

### 2. Configure Authentication

Set up OIDC authentication for secure, passwordless deployments:

→ [GitHub OIDC Setup](./github/github-oidc-setup.md)

This guide provides:
- Step-by-step OIDC configuration
- Azure AD application setup
- Federated credentials configuration

## 🏗️ Infrastructure Components

### GitHub Actions Workflows

The repository includes GitHub Actions workflows such as:

- **Hosted Agents:** `terraform-deploy-hosted-agents.yml`, `terraform-cleanup-hosted-agents.yml` (nightly destroy)
- **MCP on Azure:** `mcp-on-azure-demo.yml` (manual up/down with CLI-first `teardown.sh` + nightly down)

Workflows use Terraform with an Azure Blob backend and OIDC authentication. MCP OIDC also needs Graph app roles plus Storage Blob Data Contributor / User Access Administrator — see [GitHub OIDC Setup](./github/github-oidc-setup.md). See each lab README for how to run them.
### Terraform Modules

- **`labs/shared-modules/platform-core/`**: Shared infrastructure module
  - Resource Group
  - Virtual Network and Subnet
  - Log Analytics Workspace
  - Microsoft Foundry Cognitive Account

- **`labs/hosted-agents/`**: Hosted Agents lab configuration
  - Uses the shared platform-core module
  - Environment-specific configurations
  - Outputs for downstream consumption

## 🔐 Security Best Practices

### Terraform State Security

- **Access Control**: Use RBAC to restrict access to the storage account
- **Network Security**: Enable storage account firewall
- **Encryption**: Enable encryption for data at rest
- **Versioning**: Consider enabling blob versioning for state backup

### GitHub Secrets

**With OIDC (Recommended):**

| Secret | Description | Required |
|--------|-------------|----------|
| `ARM_CLIENT_ID` | Azure AD Application ID | ✅ |
| `ARM_SUBSCRIPTION_ID` | Azure Subscription ID | ✅ |
| `ARM_TENANT_ID` | Azure AD Tenant ID | ✅ |
| `TF_STATE_RESOURCE_GROUP` | Terraform state resource group | ✅ |
| `TF_STATE_STORAGE_ACCOUNT` | Terraform state storage account | ✅ |
| `TF_STATE_CONTAINER` | Terraform state container | ✅ |

**With Client Secrets (Alternative):**

Additionally include:
| Secret | Description | Required |
|--------|-------------|----------|
| `ARM_CLIENT_SECRET` | Service Principal Secret | ✅ |

## 📖 CAF Naming Convention

All resources follow [Microsoft Cloud Adoption Framework (CAF) naming](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming):

```
<resource-type>-<workload>-<environment>-<location-short>
```

Examples:
- `rg-hosted-agents-dev-weu` - Resource Group
- `vnet-hosted-agents-dev-weu` - Virtual Network
- `law-hosted-agents-dev-weu` - Log Analytics Workspace

Where:
- **resource-type**: `rg`, `vnet`, `snet`, `law`, etc.
- **workload**: `shared`, `hosted-agents`, etc.
- **environment**: `dev`, `staging`, `prod`
- **location-short**: `weu` (West Europe), `eus` (East US), etc.

## 🛠️ Troubleshooting

### Common Issues

**Storage account name already exists**
- Storage account names must be globally unique
- Add a random suffix: `ai0labs0pl$(date +%s)`

**Authentication failed**
- Verify all GitHub secrets are correctly set
- Check service principal permissions
- Ensure the service principal hasn't expired

**Terraform state locking**
- If state is locked, wait for the current operation to complete
- In emergencies, you can break the lock: `terraform force-unlock LOCK_ID`

## 🔗 Related Resources

- [Azure Cloud Adoption Framework](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [GitHub Actions for Terraform](https://learn.hashicorp.com/tutorials/terraform/github-actions)

## 📝 Contribution

When adding new documentation:
- Use consistent markdown formatting
- Include code examples where applicable
- Add cross-references to related documentation
- Keep examples practical and focused

## 📞 Support

For questions or issues:
1. Check the troubleshooting sections in the relevant guides
2. Review the GitHub Actions workflow logs
3. Consult the official documentation links above