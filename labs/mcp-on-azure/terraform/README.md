# Terraform - MCP on Azure

Provisions the lab stack (Foundry-free): RG, VNet, Container Apps Environment, ACR, Storage + Private Endpoint, MCP Container App (system-assigned MI), optional custom domain, Entra Easy Auth.

Lab overview (short): [../README.md](../README.md) · how to run: [../docs/run.md](../docs/run.md) · architecture: [../docs/architecture.md](../docs/architecture.md).

Remote state uses the shared lab backend (see `backend.hcl.example`). GitHub Actions: **MCP on Azure - demo up / down**.

## Prerequisites

- Azure CLI logged in with rights to the subscription **and** to create app registrations in the tenant
- Terraform >= 1.5
- `terraform.tfvars` from `terraform.tfvars.example` (gitignored)
- `backend.hcl` from `backend.hcl.example` (or `-backend-config` flags)

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

## Destroy

```bash
terraform destroy
```

Storage account names are reserved ~14 days after delete; a random suffix avoids collisions on recreate.

## Design notes

- Does **not** use `labs/shared-modules/platform-core` (avoids Foundry). Naming matches; extract a thinner shared module later if needed.
- Easy Auth uses `azapi` `authConfigs` (not an inline `azurerm_container_app` block).
- Token store is **disabled** (Bearer/API clients; no blob SAS required).
