# Hosted Agents in Azure AI Foundry

Deploy a **Hosted Agent** on Azure AI Foundry and call Azure-native tools — platform patterns first, not just a demo.

**Status:** in progress — target: demoable v1 by Aug 31, 2026

This lab explores **when to use managed agent hosting** versus self-hosted patterns (see sibling [MCP on Azure](../mcp-on-azure/) lab). The focus is the platform decision, not the agent code itself.

---

## The platform question

Teams want AI agents that can act on Azure resources. The first decision is not *which* agent framework to use, but **where it runs**:

- Self-hosted on Container Apps / AKS (full control, full ops burden)
- **Hosted Agents in Azure AI Foundry** (managed, but less control)
- Hybrid: hosted for some workloads, self-hosted for others

This lab implements the **Hosted Agents** path to compare the trade-offs honestly.

---

## What this lab does

A minimal, runnable example:

1. **Deploys** a Hosted Agent via Azure AI Foundry (Terraform)
2. **Configures** managed identity for read-only Azure access
3. **Exposes** a single tool: *list resources in a subscription via Azure Resource Graph*
4. **Documents** the platform concerns that matter for production

**What it does NOT do:**
- Write operations (slice 1 = read-only only)
- Custom container images
- Multi-region or HA patterns
- Gateway layers (APIM, App Gateway)

---

## Platform concerns (portable)

These apply regardless of the agent workload. The v1 implementation binds to Hosted Agents; the concerns map to other runtimes.

| Concern | Hosted Agents choice | Self-hosted alternative | Notes |
|---------|---------------------|------------------------|-------|
| **Runtime hosting** | Microsoft-managed | Container Apps, AKS, Functions | No VMs, patches, or scaling to manage |
| **Ingress** | Microsoft-managed endpoint | Your gateway (CA, APIM, AGW) | HTTPS + auth handled by service |
| **Downstream identity** | Managed identity | Managed identity or user pass-through | Same Azure auth patterns |
| **Network isolation** | Microsoft VNet (shared) | Your private VNet + private endpoints | Less control over networking |
| **Observability** | Built-in metrics/logs | Your App Insights, Log Analytics | Check cost of export |
| **Cost model** | Per-agent + compute tier | Your infra cost | Predictable vs variable |
| **Cold start** | ~5-10s (Microsoft SLA) | ~0-2s (your warm pool) | May matter for latency-sensitive apps |

**Key insight:** The *platform questions* stay the same. Only the *who manages the answer* changes.

---

## Architecture (v1)

```
┌──────────────┐     HTTPS (Microsoft-managed)     ┌─────────────────┐
│ Agent client │ ──────────────────────────────► │ Hosted Agent   │
│ (Cursor,     │                                       │ (Foundry)      │
│  Cline, etc.) │                                       └────────┬────────┘
└──────────────┘                                                │
                                                             managed identity ▼
                                                     ┌─────────────────────┐
                                                     │ Azure Resource Graph │
                                                     │ (read-only queries)  │
                                                     └─────────────────────┘
```

### v1 scope

| Area | Choice | Rationale |
|------|--------|-----------|
| **Runtime** | Azure AI Foundry Hosted Agents | GA feature, managed service |
| **Agent code** | Python + Azure SDK | Broad compatibility, easy to read |
| **Tool target** | Resource Graph (KQL) | Read-only, subscription-wide view |
| **Identity** | System-assigned managed identity | No secrets, Azure-native |
| **IaC** | Terraform | Your default, reproducible |

### Out of scope for v1

- User pass-through credentials (future slice)
- Write operations against Azure
- Custom backend APIs as tools
- Multi-agent orchestration
- Cost alerts or quotas (documented, not enforced)

---

## Prerequisites

- Azure subscription (lab-sized; tear down when not in use)
- Azure CLI + `az` extension for Foundry (when stable)
- Terraform >= 1.5
- Python 3.10+
- An agent client that supports Azure AI Foundry endpoints (Cursor, Cline, custom)

---

## How to run

**Not yet demoable.** Watch this folder for incremental updates.

Planned artifacts:
- `terraform/` — network + agent deployment
- `src/agent.py` — minimal agent with Resource Graph tool
- README with runnable steps

---

## Trade-offs (working notes)

Decisions for the **v1 reference implementation**. Scope is minimal; these notes capture what we learned.

| Decision | Why | When to reconsider |
|----------|-----|-------------------|
| Read-only tools first | Limits blast radius while pattern is proven | After ingress + identity are stable |
| Resource Graph target | Single Azure-native surface, no custom API | Need internal REST APIs |
| Managed identity | No secrets, Azure-native, auditable | Need user-scoped queries |
| Minimal Terraform | Deployable in <10 min, low cost | Enterprise landing zone prerequisites |

**Revisit Hosted Agents when:**
- Agent throughput exceeds Microsoft limits
- Need custom runtime (Python version, packages)
- Require air-gapped or private network deployment
- Cold start latency is unacceptable

---

## Related work

| Artifact | Link | Relationship |
|----------|------|--------------|
| MCP on Azure lab | [../mcp-on-azure/](../mcp-on-azure/) | Self-hosted pattern comparison |
| Azure AI Foundry landing zone | [Microsoft docs](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-landing-zone) | Baseline reference |
| Lab umbrella | [../../README.md](../../README.md) | All labs index |

---

## Repository layout (planned)

```
labs/hosted-agents/
├── README.md              <- you are here
├── terraform/
│   ├── main.tf           <- agent + identity
│   ├── variables.tf      <- inputs
│   └── outputs.tf        <- connection details
└── src/
    └── agent.py          <- Python agent code
```

Shared modules and ADRs may grow under repo root as patterns stabilize.

---

## License

MIT -- see [../../LICENSE](../../LICENSE).
