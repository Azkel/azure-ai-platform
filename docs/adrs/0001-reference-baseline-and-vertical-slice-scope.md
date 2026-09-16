# ADR 0001: Reference baseline and vertical slice scope

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-06-29 |
| **Updated** | 2026-09-16 - Slice 1 shipped: CA + Entra + PE Storage + `platform.*` MI and `user.*` OBO |
| **Lab** | [MCP on Azure](../../labs/mcp-on-azure/) |
| **Deciders** | Lab author |

## Context

The [MCP on Azure](../../labs/mcp-on-azure/) lab teaches **platform patterns** for hosting an MCP server safely (ingress, network isolation, downstream identity, read-only guardrails). It is a public, self-deployable reference - not an enterprise landing zone product.

We want to align with established Microsoft guidance rather than invent platform practices from scratch. Relevant bodies of work include:

- [Cloud Adoption Framework (CAF)](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/) and [Azure landing zones](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/)
- [Azure Well-Architected Framework (WAF)](https://learn.microsoft.com/en-us/azure/well-architected/) - especially security, operational excellence, and reliability pillars for AI workloads
- [Baseline Microsoft Foundry chat reference architecture in an Azure landing zone](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-landing-zone) - a concrete, WAF-aligned reference for an AI workload in an **application landing zone**, including private networking, identity, governance, and observability patterns

That Foundry landing zone article describes a **Foundry Agent Service chat workload** (web UI, Agent Service, App Service, Application Gateway, Cosmos DB, AI Search, hub-spoke networking with platform-owned shared services). **This lab does not deploy that workload.** The MCP server on Container Apps is a different application; we borrow **platform patterns**, not the chat reference stack.

The lab is intentionally a **vertical slice**: runnable on a single subscription with lab-sized cost, demoable incrementally, and portable in principle to other runtimes and gateways (AKS, APIM, etc.) as documented in the lab README.

## Decision

1. **Use the Foundry landing zone reference as the primary concrete baseline** for platform best practices where they apply to this lab (network isolation, private endpoints, managed identity, RBAC, observability mindset, WAF-aligned security thinking).

2. **Treat CAF, Azure landing zone concepts, and WAF as the principle layer** - the portable "why" behind choices. The Foundry LZ article is the closest Microsoft reference for AI + private networking in an application landing zone; it is not the only valid mapping for every enterprise stack.

3. **Scope the lab as a vertical slice** - implement only what is needed to demonstrate MCP platform concerns. Explicitly document omissions so readers do not assume the lab is an incomplete copy of the Foundry reference.

4. **Substitute the workload** - Foundry Agent Service / chat UI → **MCP server on Container Apps** with read-only tools against Azure-native targets (v1). Platform concerns stay; application components change.

5. **Defer full landing zone fidelity** - no requirement for a pre-provisioned platform landing zone (hub connectivity subscription, central Azure Firewall, Bastion, DNS Private Resolver rulesets owned by a platform team, subscription vending, dual logging to central Log Analytics, etc.) in v1.

6. **Ship both downstream identity models in Slice 1** - one MCP server exposes `platform.*` (workload MI) and `user.*` (caller token → OBO). That matches the Acceler8it teaching pair (list vs get) without a second "pass-through" release.

## Alignment matrix

| Pattern (from CAF / WAF / Foundry LZ) | v1 lab (Slice 1) | Notes |
|---------------------------------------|------------------|-------|
| Application landing zone in a dedicated subscription | Yes (simplified) | Self-contained; no platform-team dependencies |
| Spoke VNet, subnet segmentation, NSGs | Yes (simplified) | Scale down to what MCP + targets need |
| Private endpoints to PaaS | Yes | Storage PE - core "no public backdoor" story |
| Managed identity and RBAC for workload | Yes | `platform_list_blobs` via CA system-assigned MI |
| Entra-authenticated ingress | Yes | CA + Entra (JWT + PRM for MCP clients); not Application Gateway / Front Door |
| User-scoped downstream access | Yes | `user_get_blob` via OBO to Storage (delegated) |
| Read-only / guardrails before write | Yes | Lab scope |
| Observability (diagnostics, app insights) | Partial | App Insights on the CA; not full central SOC dual-ship |
| Edge WAF (Front Door / App Gateway) | No (documented omit) | Talk diagram may show Front Door; lab uses CA+Entra for the same *controlled ingress* concern |
| Hub-spoke with platform Azure Firewall | No | Cost and complexity; revisit in optional enterprise track |
| Platform-owned Bastion, UDRs, connectivity subscription | No | Assumes lab deployer owns the subscription end-to-end |
| Azure Policy / DINE from management group | No | May note as enterprise expectation; not enforced in v1 Terraform |
| Foundry resource, projects, Agent Service | No | Different workload - MCP server |
| App Service chat UI, Application Gateway + WAF | No | CA ingress chosen for v1 (see lab README trade-offs) |
| Cosmos DB, AI Search, RAG pipeline | No | Out of scope for MCP platform lab |
| APIM / AI gateway | No (v1 core) | Optional bonus track later |
| Key Vault / SQL / App Service PE grid | No | Talk scale cues only; Storage is the teaching target |

## Consequences

### Positive

- Terraform and docs can cite Microsoft reference architecture instead of ad hoc choices.
- Readers familiar with CAF/WAF/Foundry LZ recognize the networking and identity direction.
- Explicit omissions set correct expectations for a public lab vs an enterprise landing zone deployment.
- Pattern-first README remains honest: bindings vary; concerns transfer.
- Both tool credential models ship together - talk claims (slides 7-8) are demoable from one endpoint.

### Negative / accepted trade-offs

- The lab **cannot** be dropped into a real enterprise application landing zone without adaptation (DNS, firewall egress, policy conflicts, platform dependencies).
- Security reviewers may flag missing hub firewall, central logging, or WAF at Front Door / Application Gateway - those are **documented gaps**, not oversights.
- Divergence from the Foundry reference implementation repo may confuse readers who expect Agent Service or Foundry resources; ADR and lab README must repeat workload substitution.
- OBO + dual containers (`mcp-demo` vs `mcp-platform-only`) add a little Entra/RBAC complexity vs MI-only Slice 1 - accepted for teaching.

### Follow-up ADRs

Shipped:

- [0006 - MCP ingress CA + Entra](./0006-mcp-ingress-container-apps-entra.md)
- [0007 - One MCP process, two tool groups](./0007-one-mcp-process-two-tool-identity-groups.md)

Still optional until implemented:

- Front Door + WAF vs stay on CA+Entra (extends 0006)
- APIM optional track
- Internal REST fixture vs Azure-native reads only
- Thinner shared modules (extends [0003](./0003-lab-terraform-module-strategy.md))
## Alternatives considered

| Alternative | Why not chosen for v1 |
|-------------|------------------------|
| Greenfield design with no external baseline | Reinvents patterns CAF/WAF already codify; weaker credibility for a public reference lab |
| Full Foundry LZ deployment as the lab | Wrong workload (chat agent), high cost, platform LZ prerequisites, not MCP-focused |
| [Baseline Foundry chat architecture](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-chat) (non-LZ) only | Less guidance on landing zone networking and governance; LZ article better matches long-term enterprise mapping even when v1 simplifies |
| Wait until Terraform exists before any ADR | This decision governs all Terraform; recording it first avoids scope drift |
| Defer `user.*` to a later slice | Talk follow-up requires both credential models; shipping only MI under-sells slides 7-8 |

## References

- [Baseline Microsoft Foundry chat reference architecture in an Azure landing zone](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-landing-zone)
- [Baseline Microsoft Foundry chat reference architecture](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-chat) (parent baseline; workload-owned hub in simpler scenario)
- [Agent Service chat baseline reference implementation](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-landing-zone#deploy-this-scenario) (deployable sample of the LZ article - **not** deployed by this lab)
- [Azure landing zones](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/)
- [Well-Architected Framework perspective on AI workloads on Azure](https://learn.microsoft.com/en-us/azure/well-architected/ai/)
- [Lab README](../../labs/mcp-on-azure/README.md)
