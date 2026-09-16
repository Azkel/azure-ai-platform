# How to run - Hosted Agents

Back to the [lab README](../README.md).

## Prerequisites

- Azure subscription (Contributor or Owner; lab-sized spend - tear down when idle)
- Azure CLI ≥ 2.50 (`az login`)
- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) for agent deploy paths
- GitHub Actions enabled on the fork/repo
- For local agent builds: .NET 10 SDK, Docker; `jq` optional

**Region:** West Europe (`westeurope` / `weu`). Hosted Agents data-plane APIs were verified there; Poland Central control-plane can succeed while project/agent APIs return `Project not found`.

Expected wall clock: Terraform ~10-15 min, Docker deploy ~5-10 min; first demo ≤ ~30 min.

## GitHub secrets

OIDC (recommended) in repo Settings → Secrets and variables → Actions:

- `ARM_CLIENT_ID`, `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID`
- `TF_STATE_RESOURCE_GROUP`, `TF_STATE_STORAGE_ACCOUNT`, `TF_STATE_CONTAINER`

Client-secret path additionally needs `ARM_CLIENT_SECRET`. Backend setup notes: [docs/infrastructure/terraform-backend-setup.md](../../../docs/infrastructure/terraform-backend-setup.md).

## GitHub Actions

| Workflow | Role |
|----------|------|
| **Terraform Deploy - Hosted Agents** | `plan` / `apply` / `destroy` (PRs also run plan on Terraform changes) |
| **Docker Build, Push and Deploy - Hosted Agents** | Build → ACR → `azd` deploy → post-deploy RBAC |
| **Terraform cleanup** (nightly) | Destroy at 21:00 UTC unless you redeploy |

Deploy **infrastructure before** the Docker workflow. Foundry needs `allowProjectManagement=true` (Terraform sets this). Options on the Docker workflow: full pipeline, `skip-deploy`, or `deploy-only`.

Naming (lab hardcodes `dev`):

- ACR: `acrhostedagentsdevweu`
- Storage: `sthostedagentsdevweu####` (4-digit suffix for soft-delete-friendly recreate)
- Key Vault: `kv-hosted-agents-dev-weu`
- Agent: `storage-kv-agent`

## Local Terraform

```bash
cd labs/hosted-agents/terraform
# configure backend + tfvars for your subscription
terraform init -backend-config=...
terraform apply
```

Useful variables: `agent_demo_secret_value`, `agent_demo_secret_name`, `storage_blob_container_name`, `additional_storage_blob_data_contributor_principal_ids`, `additional_key_vault_secrets_user_principal_ids`.

More detail: [terraform/README.md](../terraform/README.md).

Update the demo message after apply:

```bash
az keyvault secret set \
  --vault-name kv-hosted-agents-dev-weu \
  --name agent-demo-message \
  --value "Your custom operator message"
```

## Smoke script

After both Actions workflows succeed:

```bash
cd labs/hosted-agents
./demo.sh
```

Resolves the live lab RG and exercises Key Vault + Storage tool paths. For a UI-friendly client: `cd src/hosted-agent-client && ./setup-appsettings.sh && dotnet run`.

## Invoke (CLI / REST)

```bash
azd ai agent show --name storage-kv-agent --output json
azd ai agent invoke storage-kv-agent "What is Microsoft Foundry?"
```

Or curl:

```bash
TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)
FOUNDRY_ENDPOINT="https://hosted-agents-dev-weu.services.ai.azure.com/api/projects/hosted-agents-project"

curl -X POST "$FOUNDRY_ENDPOINT/agents/storage-kv-agent/endpoint/protocols/openai/responses?api-version=v1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"input": "What is the operator demo message stored in Key Vault?", "store": true, "stream": false}'
```

Expect a blob under `notes/` in `agent-notes` after a persist/list turn.

![Hosted agent CLI: tools list](./hosted-agent-client-tools-demo.png)

## Monitor

Portal → `appi-hosted-agents-dev-weu` (Overview, Transaction search, Logs, Failures). Example KQL:

```kql
requests
| where name contains "storage-kv-agent"
| order by timestamp desc
```

```bash
azd ai agent list
azd ai agent show --name storage-kv-agent
azd ai agent version list --name storage-kv-agent
azd ai agent monitor --name storage-kv-agent
```

## Local agent process (optional)

```bash
cd labs/hosted-agents/src/storage-kv-agent
cp .env.example .env   # endpoint, model, storage, KV; grant your user RBAC
dotnet run

curl -X POST http://localhost:8088/responses \
  -H "Content-Type: application/json" \
  -d '{"input": "Hello local agent!", "stream": false}' | jq
```

Prefer the Docker Actions workflow for Foundry deploy - interactive local `azd` users may lack `agents/write` that the OIDC deployer has.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Agent not responding | `azd ai agent show` / version `active`; `azd ai agent monitor` |
| 403 on deploy / ACR | AcrPush for deployer, AcrPull for agent; `azd ai agent doctor` |
| Storage / KV 403 from agent | Docker workflow post-deploy RBAC finished; wait 1-2 min for propagation |
| Image pull failures | Tag exists in ACR; prefer digest tags for repro |
| App Insights connection string missing | Project AppInsights connection from Terraform; do not set `APPLICATIONINSIGHTS_CONNECTION_STRING` in `azure.yaml` |

Confirm agent identity roles:

```bash
AGENT_IDENTITY=$(az rest --method GET \
  --url "$FOUNDRY_ENDPOINT/agents/storage-kv-agent?api-version=v1" \
  --resource "https://ai.azure.com" \
  --query "instance_identity.principal_id" -o tsv)
az role assignment list --assignee-object-id "$AGENT_IDENTITY" --all -o table
```

## Teardown

Actions **destroy**, or nightly cleanup. Soft-delete / purge notes (Foundry purge script, KV purge, storage 14-day name reservation) are in [design.md](./design.md#cleanup-quirks).
