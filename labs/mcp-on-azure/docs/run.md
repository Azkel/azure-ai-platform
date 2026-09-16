# How to run - MCP on Azure

Back to the [lab README](../README.md).

## Prerequisites

- Azure subscription (lab-sized spend; tear down when not in use)
- Terraform ≥ 1.5
- Azure CLI (logged in)
- .NET 10 SDK (local build) or `az acr build` for cloud builds
- `jq` + `python3` for `demo.sh`
- An MCP-capable client (VS Code / Cursor) for the interactive demo

## GitHub Actions (talk / meetup)

The shared hostname `mcp.azure.smyk.it` is **not always online**. It is brought up for demos/talks and destroyed afterward (nightly `down` is a safety net). Outside those windows, deploy your own stack.

Workflow: **MCP on Azure - demo up / down** (`.github/workflows/mcp-on-azure-demo.yml`).

| Action | When |
|--------|------|
| **up** | Before the talk - Terraform apply, ACR build, custom domain cert, seed blob |
| **down** | After - destroy stack (also runs nightly at 21:00 UTC as a safety net) |

When **up** finishes, the run log / job summary prints landing URL, MCP endpoint, and Entra tenant / client / scope.

Requires the same GitHub `dev` environment secrets as Hosted Agents (`AZURE_*`, `TF_STATE_*`), plus DNS write on `azure.smyk.it` for the custom hostname.

**Microsoft Graph app roles on the OIDC app** (required — Azure RBAC alone is not enough). Without these, `terraform apply` / `destroy` fails refreshing Entra data sources with `403 Authorization_RequestDenied`:

| Application permission | Why this lab needs it |
|------------------------|------------------------|
| `Application.ReadWrite.All` | Create / update / delete `mcp-on-azure-<env>` app registration |
| `Directory.Read.All` | Resolve first-party service principals (Microsoft Graph, Azure Storage) |
| `DelegatedPermissionGrant.ReadWrite.All` | Grant Graph `User.Read` + Storage `user_impersonation` for OBO |

Also grant Azure RBAC **`Storage Blob Data Contributor`** (and ideally **`User Access Administrator`**) on the subscription to the same OIDC app — control-plane **Contributor** cannot seed blobs or create data-plane role assignments. See [OIDC setup Step 3c](../../../docs/github/github-oidc-setup.md#step-3c-storage-data-plane--role-assignment-rights-mcp-on-azure).

Full Graph grant commands: [GitHub OIDC setup — Step 3b](../../../docs/github/github-oidc-setup.md#step-3b-microsoft-graph-app-roles-mcp-on-azure).

## Local deploy

```bash
cd labs/mcp-on-azure/terraform
cp terraform.tfvars.example terraform.tfvars
# set subscription_id, optional custom_hostname / DNS zone, mcp_image after first ACR build
cp backend.hcl.example backend.hcl
terraform init -migrate-state -backend-config=backend.hcl
terraform apply

# build/push image (cloud)
az acr build -r <acr_name> -g <rg> -t mcp-on-azure:0.1.6 ../src
# set mcp_image in tfvars, apply again

# custom domain: after first hostname create, bind managed cert
./scripts/bind-custom-domain.sh

cd ..
./demo.sh
```

More Terraform detail: [terraform/README.md](../terraform/README.md).

## Connect a client

1. Open the landing page when the demo stack is up (e.g. `https://mcp.azure.smyk.it/`) - no auth. Otherwise use your own apply URL from Terraform outputs.
2. Copy the VS Code / Cursor `mcp.json` and start the server - Entra sign-in should prompt (OAuth via Protected Resource Metadata).
3. Call `platform_list_blobs` (app MI) and `user_get_blob` (your identity).

CLI token fallback (Azure CLI is pre-authorized for the lab API scope):

```bash
SCOPE=$(terraform -chdir=terraform output -raw entra_scope)
TOKEN=$(az account get-access-token --scope "$SCOPE" --query accessToken -o tsv)
```

Auth model on the host:

- Easy Auth is **AllowAnonymous** so unauthenticated `/mcp` reaches the app and returns `401` with `WWW-Authenticate` + `resource_metadata`.
- The app validates JWTs on `/mcp` and serves `/.well-known/oauth-protected-resource`.
- Landing `/`, `/config.json`, `/health`, and PRM paths stay anonymous.

```bash
# expect 401 + resource_metadata
curl -sS -D - -o /dev/null -X POST https://mcp.azure.smyk.it/mcp \
  -H 'content-type: application/json' -d '{}' | grep -i www-authenticate
```

| Tool | Identity |
|------|----------|
| `platform_list_blobs` | Container App managed identity |
| `user_get_blob` | Caller → OBO → Storage. Data Reader on `mcp-demo` only; `mcp-platform-only` stays MI-only |

After apply, grant meetup callers (or yourself) demo-only Reader on `mcp-demo` — **not** via core Terraform:

```bash
cd labs/mcp-on-azure/terraform
./scripts/grant-demo-blob-reader.sh                  # signed-in user
./scripts/grant-demo-blob-reader.sh <entra-object-id>
# CI: set repo variable DEMO_BLOB_READER_OBJECT_IDS (comma-separated)
```

## Smoke script

```bash
./demo.sh
# or against a known endpoint:
MCP_ENDPOINT=https://mcp.azure.smyk.it \
MCP_SCOPE='https://mcp.azure.smyk.it/mcp/access_as_user' \
./demo.sh
```

Checks: health → unauthenticated 401 → token → list (MI) → get `hello.txt` (OBO) → optional deny on platform-only if that blob is seeded.

## Audit note

Tool calls run as either the **workload MI** or the **signed-in caller** (OBO). Container Apps + Application Insights capture host telemetry; Storage data-plane access follows whichever identity the tool used. Enough for a meetup "why pass-through matters" story - not a full SOC pipeline.

## Teardown

Prefer the GitHub **down** workflow (or nightly schedule) so remote state stays consistent. It runs `terraform/scripts/teardown.sh`, which deletes Container Apps / the CAE via Azure CLI (with RG-delete fallback) before finishing Entra + DNS with Terraform — plain `terraform destroy` often hangs on `ScheduledForDelete`.

```bash
cd labs/mcp-on-azure/terraform
./scripts/teardown.sh   # after init; pass the same -var flags as apply
```

Storage account names are reserved for a period after delete; the lab uses a random suffix to allow recreate. Note any destroy residuals if Azure leaves orphaned links (same class of issue as Hosted Agents).
