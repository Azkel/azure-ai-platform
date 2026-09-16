# Terraform - MCP on Azure

Provisions the lab stack (Foundry-free): RG, VNet, Container Apps Environment, ACR, Storage + Private Endpoint, MCP Container App (system-assigned MI), optional custom domain, Entra Easy Auth.

Lab overview (short): [../README.md](../README.md) · how to run: [../docs/run.md](../docs/run.md) · architecture: [../docs/architecture.md](../docs/architecture.md).

Remote state uses the shared lab backend (see `backend.hcl.example`). GitHub Actions: **MCP on Azure - demo up / down**.

## Prerequisites

- Azure CLI logged in with rights to the subscription **and** to create app registrations in the tenant
- Terraform >= 1.5
- `terraform.tfvars` from `terraform.tfvars.example` (gitignored)
- `backend.hcl` from `backend.hcl.example` (or `-backend-config` flags)

### GitHub Actions OIDC (Graph)

The Actions deployer needs **Microsoft Graph application permissions**, not only Azure RBAC. Hosted Agents can deploy with Contributor + state storage; this lab also manages Entra apps and delegated grants via the `azuread` provider.

| Application permission | Purpose |
|------------------------|---------|
| `Application.ReadWrite.All` | Lab app registration lifecycle |
| `Directory.Read.All` | Look up Graph / Storage service principals |
| `DelegatedPermissionGrant.ReadWrite.All` | OBO consent grants (`User.Read`, Storage `user_impersonation`) |

Missing these shows up as `403` on `data.azuread_service_principal.*` during plan/apply/destroy. How to grant: [OIDC setup Step 3b](../../../docs/github/github-oidc-setup.md#step-3b-microsoft-graph-app-roles-mcp-on-azure) · also summarized in [docs/run.md](../docs/run.md#github-actions-talk--meetup).

## Apply (local)

```bash
cd labs/mcp-on-azure/terraform
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
# edit subscription_id, custom domain, mcp_image
terraform init -migrate-state -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

After the first custom-domain create, bind the managed cert:

```bash
./scripts/bind-custom-domain.sh
```

## Entra

With `enable_entra_auth = true` (default):

- Creates app registration `mcp-on-azure-<env>` with scope `access_as_user`
- Grants Graph `User.Read` + Storage `user_impersonation` (for OBO)
- Pre-authorizes Azure CLI for the API scope
- Enables Container Apps auth (`AllowAnonymous` + app JWT on `/mcp`; PRM at `/.well-known/oauth-protected-resource`)
- Pre-authorizes Azure CLI and VS Code for the API scope
- Registers HTTPS Application ID URIs (`https://<host>` and `https://<host>/mcp`) when a custom domain is set

```bash
terraform output entra_client_id
terraform output entra_scope
```

## Demo RBAC (post-apply script)

Meetup `user_get_blob` needs **Storage Blob Data Reader** on `mcp-demo` only. That grant is intentionally **not** core Terraform — run after apply:

```bash
./scripts/grant-demo-blob-reader.sh
# or: DEMO_BLOB_READER_OBJECT_IDS=oid1,oid2 ./scripts/grant-demo-blob-reader.sh
```

Does not touch `mcp-platform-only` (deny demo). GitHub **up** runs the same script when repo variable `DEMO_BLOB_READER_OBJECT_IDS` is set.

## Destroy

Prefer the GitHub **down** workflow (it runs `scripts/teardown.sh`). Plain `terraform destroy` often hangs on a VNet-injected Container Apps Environment stuck in `ScheduledForDelete`.

```bash
# Local (same path as CI):
./scripts/teardown.sh \
  -var="subscription_id=$SUB" \
  -var="custom_hostname=mcp.azure.smyk.it" \
  -var="dns_zone_name=azure.smyk.it" \
  -var="dns_zone_resource_group_name=rg-shared-plc-prod"

# Escape hatch only:
terraform destroy
```

`teardown.sh` deletes Container Apps via Azure CLI, waits on CAE delete, falls back to **resource group delete** if the CAE is still stuck, prunes gone resources from state, then `terraform destroy` for Entra + shared DNS.

Storage account names are reserved ~14 days after delete; a random suffix avoids collisions on recreate.

## Design notes

- Does **not** use `labs/shared-modules/platform-core` (avoids Foundry). Naming matches; extract a thinner shared module later if needed.
- Easy Auth uses `azapi` `authConfigs` (not an inline `azurerm_container_app` block).
- Token store is **disabled** (Bearer/API clients; no blob SAS required).
