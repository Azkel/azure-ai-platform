# MCP on Azure

Host a [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server on Azure with platform defaults — private networking, managed identity, and a read-only posture first.

**Status:** in progress — architecture and Terraform are being built incrementally. Not runnable yet.

This lab ships **one runnable Azure path** so you can deploy and experiment. The goal is the **platform pattern** (ingress, isolation, identity, guardrails), not a mandate to use these exact services. Your enterprise may use AKS, self-hosted Kubernetes, APIM, App Gateway, or another edge — the concerns stay the same; the bindings change.

---

## Problem

Teams want AI assistants (Cursor, Cline, Copilot, custom agents) to call **internal APIs and Azure resources** through MCP. Running an MCP server like any other app is easy; running it **safely on a platform** is not:

- Ingress and authentication at the edge (who can connect?)
- Network isolation (MCP should not become a public backdoor into a VNet)
- Credential flow (pass-through user tokens vs managed identity for the server)
- Observability and guardrails before write-capable tools ship

This lab explores those platform decisions with a minimal, demoable path — not a full enterprise landing zone.

---

## Reference baseline

Platform choices align with [CAF](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/), [Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/), and the [Baseline Microsoft Foundry landing zone](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-landing-zone) reference — **selectively**, not as a full deployment. This lab is a **vertical slice**: same class of concerns (private networking, identity, guardrails), different workload (MCP on Container Apps, not Foundry Agent Service chat), and many enterprise landing zone components intentionally omitted for cost and simplicity.

See **[ADR 0001: Reference baseline and vertical slice scope](../../docs/adrs/0001-reference-baseline-and-vertical-slice-scope.md)** for the alignment matrix and explicit omissions.

---

## Platform concerns (portable)

These apply regardless of runtime or gateway. The v1 reference implementation binds them to Container Apps and Entra; see [Mapping to other stacks](#mapping-to-other-stacks).

| Concern | What it means |
|---------|----------------|
| Controlled ingress | Only authenticated clients reach the MCP endpoint (TLS + identity at the edge) |
| Isolated runtime | MCP runs inside a private boundary, not as a public shortcut into internal networks |
| Downstream identity | Each tool uses an explicit auth model — workload identity or user-scoped token — not an implicit default |
| Guardrails first | Read-only tools until ingress and identity are proven; write capability comes later |
| Deployable and teardown-friendly | IaC, predictable cost for a public try-it-yourself lab |

---

## Intended architecture (v1)

High-level target. Binding choices land in Terraform and further ADRs as code ships ([ADR 0001](../../docs/adrs/0001-reference-baseline-and-vertical-slice-scope.md) records baseline alignment and slice scope).

```
┌──────────────┐     HTTPS + Entra     ┌─────────────────┐
│ MCP client   │ ────────────────────► │ Ingress         │
│ (Cursor,     │                       │ (Container Apps │
│  Cline, …)   │                       │  + Entra auth)  │
└──────────────┘                       └────────┬────────┘
                                                │
                                       private  │
                                       network  ▼
                                       ┌─────────────────┐
                                       │ MCP server      │
                                       │ (Container Apps)│
                                       │                 │
                                       │  platform.*     │── managed identity
                                       │  user.*         │── caller's token
                                       └────────┬────────┘
                                                │
                              private endpoints │
                                                ▼
                                       ┌─────────────────┐
                                       │ Azure targets   │
                                       │ (read-only v1)  │
                                       └─────────────────┘
```

### One MCP server, two auth patterns

A single .NET MCP server exposes **two tool groups** with different downstream identity — not two separate deployments:

| Tool group | Auth model | Downstream identity | Example (illustrative) |
|------------|------------|---------------------|-------------------------|
| `platform.*` | Managed identity | The MCP workload | List blobs using the app's RBAC |
| `user.*` | Caller's access token (pass-through) | The connected user | List blobs the caller is allowed to see |

Ingress auth (Entra at the edge) answers **who may call MCP**. Tool auth answers **whose Azure permissions apply** for that invocation. Do not mix both models in one tool.

**Delivery order:**

1. **Slice 1** — `platform.*` tools only (managed identity, read-only Azure calls). Gets the stack demoable quickly.
2. **Slice 2** — `user.*` tools on the same server and the same Azure surfaces, to compare behavior and audit implications.

### v1 scope

| Area | Choice |
|------|--------|
| Runtime | Azure Container Apps |
| MCP server | Single .NET app (`src/`), two tool groups as above |
| Tool targets | Read-only Azure surfaces (e.g. Storage, Resource Graph) — no custom backend app in v1 |
| Tools | Read-only first |
| IaC | Terraform (network + runtime) |
| Ingress | Container Apps + Entra (see [trade-offs](#trade-offs-working-notes)) |
| Identity | Managed identity first; user pass-through in slice 2 |

### Out of scope for v1

- Custom business applications as MCP backends (optional REST fixture may come later as test infrastructure)
- Write-capable tools
- APIM or other gateway layers (optional [bonus track](#optional-tracks), not required for the core lab)

---

## What you'll be able to do (when demoable)

1. Deploy the lab stack with Terraform.
2. Connect an MCP client to the hosted endpoint.
3. Invoke **read-only** `platform.*` tools against Azure (slice 1), then **read-only** `user.*` tools for comparison (slice 2).
4. Review trade-offs here and in linked ADRs / blog posts as they ship.

---

## Mapping to other stacks

The reference lab uses Container Apps. In other environments, map the same concerns roughly as follows:

| v1 binding | Common alternatives |
|------------|---------------------|
| Container Apps | AKS, self-hosted Kubernetes, other orchestrators |
| CA ingress + Entra | APIM, App Gateway, Ingress + OIDC, corporate API gateway |
| Workload managed identity | Kubernetes service account + Azure Workload Identity |
| Private endpoints to Azure | Same Azure networking model; cluster needs VNet integration |

You do not need every alternative implemented in this repo to apply the pattern — the checklist in [Platform concerns](#platform-concerns-portable) is the portable part.

---

## Optional tracks

These are **side paths** for readers who want to go deeper. They are not required to understand or run the core lab.

| Track | Purpose |
|-------|---------|
| **APIM in front of CA** | Gateway policies (rate limits, path-based auth, multi-backend front door). Higher fixed cost; documented when added. |
| **Internal REST API fixture** | Prove MCP → private HTTP API routing using a pinned mock container, not a maintained application. |
| **AKS / other runtimes** | Notes or modules mapping the same pattern to a different orchestrator. |

---

## Repository layout (planned)

Artifacts appear here as they ship — not upfront scaffolding.

```
labs/mcp-on-azure/
├── README.md           ← you are here
├── terraform/          ← network, Container Apps, ingress (planned)
└── src/                ← MCP server (.NET) (planned)
```

Shared modules and ADRs may grow under repo root (`infra/modules/`, `docs/adrs/`) as patterns stabilize.

### Documentation approach

| Artifact | When |
|----------|------|
| This README | Intent, options, and working decisions |
| [ADR 0001](../../docs/adrs/0001-reference-baseline-and-vertical-slice-scope.md) | Reference baseline and vertical slice scope (accepted) |
| Further ADRs under `docs/adrs/` | With Terraform or code that commits each binding choice |
| Blog post | When the first slice is demoable |

---

## Prerequisites (planned)

- Azure subscription (lab-sized spend; tear down when not in use)
- Terraform ≥ 1.5
- .NET SDK (version pinned when `src/` lands)
- An MCP-capable client for the demo (e.g. Cursor)

Exact versions and bootstrap steps will be documented when the first runnable slice exists.

---

## How to run

**Not yet.** Watch this folder and [repo commits](https://github.com/Azkel/azure-ai-platform/commits/main) for incremental updates.

---

## Trade-offs (working notes)

Decisions for the **v1 reference implementation**. Scope and baseline alignment are in [ADR 0001](../../docs/adrs/0001-reference-baseline-and-vertical-slice-scope.md); binding choices below will gain dedicated ADRs as code lands.

| Topic | v1 choice | Why |
|-------|-----------|-----|
| Read-only tools first | Yes | Limits blast radius while ingress and identity are proven |
| Container Apps vs AKS | Container Apps | Lower ops and cost for a single MCP workload; pattern maps to K8s later |
| APIM vs CA-native ingress | **CA + Entra** | Meets v1 edge requirements with fewer components and lower fixed cost for a public self-deploy lab; APIM deferred to [optional track](#optional-tracks) |
| Custom backend vs Azure-native targets | Azure-native in v1 | Lab focus is platform (network, identity, ingress), not application development |
| Managed identity vs pass-through | Both, sequenced | One server, distinct tool groups; MI in slice 1, pass-through in slice 2 for apples-to-apples comparison |
| User token pass-through | Slice 2 | Needed for user-scoped queries; token exchange on behalf of the caller and audit complexity documented when implemented |

**Revisit APIM / gateway layer when:** tool-path authorization at the edge, rate limiting, or multiple backends behind one URL become in-scope — not merely to learn the product.

---

## Related work

| Artifact | Link |
|----------|------|
| ADR 0001 — reference baseline & vertical slice | [docs/adrs/0001-reference-baseline-and-vertical-slice-scope.md](../../docs/adrs/0001-reference-baseline-and-vertical-slice-scope.md) |
| AI tooling for Azure DevOps (talk repo) | [AiNowPolska-June2026](https://github.com/Azkel/AiNowPolska-June2026) |
| Labs umbrella | [README](../../README.md) |
| Blog (when lab is demoable) | [blog.smyk.it](https://blog.smyk.it/) |

---

## License

MIT — see [`LICENSE`](../../LICENSE).
