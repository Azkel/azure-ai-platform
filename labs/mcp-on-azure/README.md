# MCP on Azure

Host an [MCP](https://modelcontextprotocol.io/) server on Azure the **platform** way: Entra at the door, private network, managed identity **and** caller identity for tools - read-only first.

**Status:** Demoable v1 (stack is **ephemeral** - up for talks/meetups, then torn down; not a 24/7 public service)  
**Demo host (when up):** [https://mcp.azure.smyk.it](https://mcp.azure.smyk.it) - landing + VS Code config. If TLS fails or the host is down, use the default Container Apps FQDN from Terraform outputs (`mcp_endpoint` / `mcp_default_fqdn`) or deploy your own.

```
Client → Entra → Container Apps (MCP)
                      ├─ platform_list_blobs  → Storage (app MI — lists mcp-demo + mcp-platform-only)
                      └─ user_get_blob        → Storage (your token / OBO — hello.txt OK; platform-only → 403)
                              ↑ Private Endpoint
```

Not a full landing zone - one vertical slice you can deploy and tear down. Patterns transfer to AKS, APIM, Front Door, etc.; this lab binds them to Container Apps + Entra.

---

## Quick start

**During a live demo window** (author brings the stack up via Actions; not always online): open the landing page → copy `mcp.json` into VS Code → sign in when prompted → call the two tools.

**Smoke without a GUI** (needs `az login` + stack currently up):

```bash
cd labs/mcp-on-azure
MCP_ENDPOINT=https://mcp.azure.smyk.it \
MCP_SCOPE='https://mcp.azure.smyk.it/mcp/access_as_user' \
./demo.sh
```

**Deploy your own** (default path if the shared host is down):

```bash
cd labs/mcp-on-azure/terraform
cp terraform.tfvars.example terraform.tfvars   # set subscription_id (+ DNS if you want a custom host)
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
terraform apply
# build image into the lab ACR, set mcp_image, apply again - details in docs/run.md
./scripts/grant-demo-blob-reader.sh            # demo-only: mcp-demo Reader for user_get_blob
cd .. && ./demo.sh
```

**Teardown:** GitHub workflow **MCP on Azure - demo up / down** → `down` (runs `terraform/scripts/teardown.sh`), or locally `./scripts/teardown.sh`. Plain `terraform destroy` often hangs on CAE `ScheduledForDelete`.

**CI note:** the GitHub OIDC app needs Microsoft Graph application roles (`Application.ReadWrite.All`, `Directory.Read.All`, `DelegatedPermissionGrant.ReadWrite.All`) plus Azure RBAC **Storage Blob Data Contributor** and **User Access Administrator** — see [How to run](./docs/run.md#github-actions-talk--meetup).

---

## Docs (details live here)

| Doc | What's in it |
|-----|----------------|
| [Architecture](./docs/architecture.md) | Why this lab, portable concerns, diagram, MI vs OBO tools, talk vs Slice 1 |
| [How to run](./docs/run.md) | Prerequisites, GitHub Actions (+ Graph / data-plane roles), local Terraform, auth smoke, teardown |
| [Design notes](./docs/design.md) | Trade-offs, optional tracks, other stacks, baseline / ADR |
| [Terraform](./terraform/README.md) | Providers, Entra wiring, OIDC roles, seed blobs, demo RBAC script, teardown |

Repo ADRs: [index](../../docs/adrs/README.md) · [0001 vertical slice](../../docs/adrs/0001-reference-baseline-and-vertical-slice-scope.md) · [0006 ingress](../../docs/adrs/0006-mcp-ingress-container-apps-entra.md) · [0007 tool groups](../../docs/adrs/0007-one-mcp-process-two-tool-identity-groups.md).

---

## Layout

```
labs/mcp-on-azure/
├── README.md       ← you are here
├── docs/           ← deeper pages
├── demo.sh         ← health + 401 + list + get hello.txt + deny on platform-only
├── deploy-and-validate.sh
├── terraform/      ← incl. scripts/teardown.sh, grant-demo-blob-reader.sh
└── src/            ← .NET MCP + Razor landing
```

---

## License

MIT - see [`LICENSE`](../../LICENSE).
