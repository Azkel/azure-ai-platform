# Design notes - MCP on Azure

Back to the [lab README](../README.md).

## Reference baseline

Platform choices align with [CAF](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/), [Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/), and the [Baseline Microsoft Foundry landing zone](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-landing-zone) - **selectively**, not as a full deployment.

Same class of concerns (private networking, identity, guardrails), different workload (MCP on Container Apps, not Foundry Agent Service chat). Many enterprise LZ components are intentionally omitted for cost and simplicity.

Full matrix and omissions: **[ADR 0001](../../../docs/adrs/0001-reference-baseline-and-vertical-slice-scope.md)**.

## Trade-offs (v1)

| Topic | v1 choice | Why |
|-------|-----------|-----|
| Read-only tools first | Yes | Limits blast radius while ingress and identity are proven |
| Container Apps vs AKS | Container Apps | Lower ops and cost for a single MCP workload; pattern maps to K8s later |
| Front Door / WAF vs CA+Entra | **CA + Entra** | Meets controlled-ingress for a public lab; Front Door is talk-diagram / optional hardening |
| APIM vs CA-native ingress | **CA + Entra** | Fewer components and lower fixed cost |
| Custom backend vs Azure-native targets | Azure-native in v1 | Focus is platform (network, identity, ingress), not app development |
| Managed identity vs caller pass-through | **Both in Slice 1** | One server, distinct tool groups - Acceler8it teaching pair |

**Revisit Front Door / APIM when:** edge WAF, multi-backend routing, or gateway policies become in-scope - not merely to match the talk diagram SKU-for-SKU.

## Mapping to other stacks

| v1 binding | Common alternatives |
|------------|---------------------|
| Container Apps | AKS, self-hosted Kubernetes, other orchestrators |
| CA ingress + Entra | Front Door + WAF, APIM, App Gateway, Ingress + OIDC |
| Workload managed identity | Kubernetes service account + Azure Workload Identity |
| Private endpoints to Azure | Same Azure networking model; cluster needs VNet integration |

You do not need every alternative in this repo - the [portable concerns](./architecture.md#portable-platform-concerns) are the transferable part.

## Optional tracks

Not required to understand or run the core lab:

| Track | Purpose |
|-------|---------|
| **Front Door + WAF** | Closer to the Acceler8it slide-10 edge |
| **APIM in front of CA** | Gateway policies, multi-backend front door; higher fixed cost |
| **Internal REST API fixture** | MCP → private HTTP API with a pinned mock container |
| **AKS / other runtimes** | Same pattern on a different orchestrator |

## Related

| Artifact | Link |
|----------|------|
| ADR index | [docs/adrs/](../../../docs/adrs/README.md) |
| ADR 0001 - vertical slice | [0001](../../../docs/adrs/0001-reference-baseline-and-vertical-slice-scope.md) |
| ADR 0004 - MI / OBO | [0004](../../../docs/adrs/0004-workload-mi-and-caller-obo-patterns.md) |
| ADR 0006 - MCP ingress | [0006](../../../docs/adrs/0006-mcp-ingress-container-apps-entra.md) |
| Architecture | [architecture.md](./architecture.md) |
| How to run | [run.md](./run.md) |
| Labs umbrella | [../../../README.md](../../../README.md) |
| Blog | [blog.smyk.it](https://blog.smyk.it/) |
