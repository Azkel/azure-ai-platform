# Architecture - MCP on Azure

Back to the [lab README](../README.md).

## Problem

Teams want AI assistants (VS Code, Cursor, Cline, custom agents) to call **internal APIs and Azure resources** through MCP. Running an MCP server like any other app is easy; running it **safely on a platform** is not:

- Ingress and authentication at the edge (who can connect?)
- Network isolation (MCP should not become a public backdoor into a VNet)
- Credential flow (pass-through user tokens vs managed identity for the server)
- Observability and guardrails before write-capable tools ship

This lab is a minimal, demoable path - not a full enterprise landing zone.

## Portable platform concerns

These apply regardless of runtime or gateway. v1 binds them to Container Apps and Entra; see [Design notes - other stacks](./design.md#mapping-to-other-stacks).

| Concern | What it means |
|---------|----------------|
| Controlled ingress | Only authenticated clients reach the MCP endpoint (TLS + identity at the edge) |
| Isolated runtime | MCP runs inside a private boundary, not as a public shortcut into internal networks |
| Downstream identity | Each tool uses an explicit auth model - workload identity or user-scoped token - not an implicit default |
| Guardrails first | Read-only tools until ingress and identity are proven; write capability comes later |
| Deployable and teardown-friendly | IaC, ephemeral demo windows (not always online), predictable cost |

## Architecture (v1)

```
┌──────────────┐     HTTPS + Entra     ┌─────────────────┐
│ MCP client   │ ────────────────────► │ Ingress         │
│ (VS Code,    │                       │ (Container Apps │
│  Cursor, ...)  │                       │  + Entra / JWT) │
└──────────────┘                       └────────┬────────┘
                                                │
                                       private  │
                                       network  ▼
                                       ┌─────────────────┐
                                       │ MCP server      │
                                       │ (Container Apps)│
                                       │                 │
                                       │  platform.*     │── managed identity
                                       │  user.*         │── caller's token (OBO)
                                       └────────┬────────┘
                                                │
                              private endpoints │
                                                ▼
                                       ┌─────────────────┐
                                       │ Azure Storage   │
                                       │ (read-only v1)  │
                                       └─────────────────┘
```

### One server, two auth patterns

Ingress auth (Entra) answers **who may call MCP**. Tool auth answers **whose Azure permissions apply**. Do not mix both models in one tool.

| Tool group | Auth model | Downstream identity | Teaching example |
|------------|------------|---------------------|------------------|
| `platform.*` | Managed identity | The MCP workload | `platform_list_blobs` - list `mcp-demo` + `mcp-platform-only` |
| `user.*` | Caller's token (OBO) | The connected user | `user_get_blob` — `hello.txt` allowed (needs demo Reader on `mcp-demo` via `grant-demo-blob-reader.sh`); `mcp-platform-only/platform-only.txt` → 403. MI `platform_list_blobs` still lists both. |

### Slice 1 vs Acceler8it talk diagram

Follow-up lab for the **Acceler8it 2026** talk. The talk path may show a fuller edge; Slice 1 keeps the same portable concerns with fewer SKUs:

| Talk / diagram element | Slice 1 lab | Notes |
|------------------------|-------------|-------|
| MCP client | Yes (demo) | Landing page + VS Code OAuth / CLI token |
| Entra at ingress | Yes | JWT + Protected Resource Metadata |
| Front Door + WAF | **Omitted** | Same *controlled ingress* concern; CA+Entra is the v1 binding |
| VNet + CA Environment | Yes | Delegated subnet |
| MCP on Container Apps | Yes | .NET HTTP MCP |
| MI + RBAC | Yes | `platform_list_blobs` |
| Caller / delegated identity | Yes | `user_get_blob` (OBO) |
| Private Endpoint → Storage | Yes | Teaching target |
| Key Vault / SQL / App Service / internal API PE | Docs only | Talk scale cues - not deployed |
| APIM | Out | Skip-slide topic; [optional later](./design.md#optional-tracks) |

### v1 scope

| Area | Choice |
|------|--------|
| Runtime | Azure Container Apps |
| MCP server | Single .NET app (`src/`) |
| Tool targets | One Storage account + Private Endpoint (read-only) |
| Tools | `platform_list_blobs` + `user_get_blob` |
| IaC | Terraform under `terraform/` |
| Ingress | CA + Entra (JWT; Easy Auth AllowAnonymous so PRM challenges reach clients) |
| Identity | Workload MI **and** caller OBO on the same server |

### Out of scope for v1

- Custom business backends / write-capable tools
- Front Door / App Gateway WAF, APIM, Key Vault PE, SQL PE (documented omissions)
- Full enterprise hub-spoke / platform landing zone

Baseline alignment: [ADR 0001](../../../docs/adrs/0001-reference-baseline-and-vertical-slice-scope.md).
