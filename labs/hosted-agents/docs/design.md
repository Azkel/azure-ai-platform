# Design notes - Hosted Agents

Back to the [lab README](../README.md).

## Reference baseline

Aligns selectively with CAF / Well-Architected and Foundry landing-zone ideas (private networking, identity, observability) - not a full LZ deploy. Shared Foundry surface lives in `platform-core`; lab-local resources stay in this lab's Terraform ([ADR 0003](../../../docs/adrs/0003-lab-terraform-module-strategy.md)).

## What this lab deploys

**From `platform-core`:** resource group, VNet/subnet, Log Analytics, Microsoft Foundry Cognitive Account (AIServices), Application Insights linked for agent injection.

**Lab-local:** ACR, Key Vault (RBAC + demo secret + App Insights connection string secret as needed), Storage (Azure AD only) + `agent-notes` container, Foundry project, model deployment (`gpt-5-mini` by default).

## Trade-offs (v1)

| Decision | Why | Alternative considered |
|----------|-----|------------------------|
| Azure RBAC for Key Vault | Simple with recreate cycles | Access policies - heavier churn |
| BYO Responses (.NET) | Full control over tools and loop | Hosted native agent SDKs - less flexible for this sample |
| Agent instance MI for tools | No secrets in image | SP / API keys in env |
| Storage Azure AD only | No key rotation in the lab | Shared access keys |
| GitHub Actions + OIDC | No long-lived deploy secrets | Client secret SP |
| Terraform | Mature, matches repo | Bicep-only path |
| Daily auto-cleanup | Caps forgotten spend | Manual destroy only |
| 4-digit storage suffix | Soft-delete name collision (~14 days, no purge API) | Static names |

**Revisit when:** production SKUs, multi-instance scale, GPU, or long-running jobs are in scope - not for this demo lab.

## Known limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| Region | Data-plane verified in West Europe | Use `westeurope` |
| Soft-delete storage names | ~14 day reservation | Random 4-digit suffix |
| App Insights injection | Needs project AppInsights connection | Terraform creates it |
| RBAC propagation | 1-2 min after deploy | Wait before first invoke |
| Model quota / availability | `gpt-5-mini` may be constrained | Swap deployment name |
| Local `azd deploy` | Interactive user may lack `agents/write` | Use Docker Actions workflow |
| Foundry concurrency | Model deploy + project create can 409 | Terraform serializes + retries |

## Cost posture

- Log Analytics 30-day retention; Foundry S0; Storage Standard LRS; West Europe
- Nightly destroy at 21:00 UTC
- Rough order: a few USD/day while up (Foundry + model + Storage + KV + ACR + App Insights) - treat as ephemeral

Scaling notes: S0, low model TPM, 0.5 CPU / 1Gi agent, single instance - demo only. Production would need higher SKUs, capacity, and multi-instance patterns Foundry supports at the time.

## Cleanup quirks

Destroyed with the RG / Terraform: VNet, subnet, storage account, model deployment, etc.

| Resource | Soft-delete behavior |
|----------|----------------------|
| Storage account | ~14 day recovery window; **no purge API** - suffix avoids name clash ([docs](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-recover)) |
| Blob soft-delete | Disabled on lab SA so destroy does not leave soft-deleted blobs inside the account |
| Key Vault | Provider `purge_soft_delete_on_destroy = true` when allowed |
| Foundry / Cognitive account | Soft-delete; purge via script after network-injection teardown (inline provider purge races 409) |
| ACR | Soft delete + retention; auto-purge later |
| App Insights | Smart Detection rules can block deletion occasionally |

```bash
labs/hosted-agents/terraform/scripts/purge-soft-deleted-foundry.sh \
  westeurope rg-hosted-agents-dev-weu cog-hosted-agents-dev-weu

az keyvault purge --name kv-hosted-agents-dev-weu --location westeurope
# Storage: wait out recovery window - no purge command
```

## When to use this pattern vs alternatives

**Fit:** managed agent hosting, Azure identity/network/monitoring integration, request-style workloads, Azure resource tools from the agent, BYO container control.

**Consider something else when:** GPU (ACA/AKS), long-running jobs (Functions / ACA Jobs), custom scale operators (AKS), non-Azure runtimes, or simple low-latency prompts that do not need an agent host.

## Related

| Artifact | Link |
|----------|------|
| ADR index | [docs/adrs/](../../../docs/adrs/README.md) |
| ADR 0002 - OIDC / state | [0002](../../../docs/adrs/0002-github-oidc-and-remote-terraform-state.md) |
| ADR 0003 - modules | [0003](../../../docs/adrs/0003-lab-terraform-module-strategy.md) |
| ADR 0004 - MI patterns | [0004](../../../docs/adrs/0004-workload-mi-and-caller-obo-patterns.md) |
| Architecture | [architecture.md](./architecture.md) |
| How to run | [run.md](./run.md) |
| Blog cousin | [Chat, files, and Terraform](https://smyk.it/posts/2026/azure-ai-foundry-terraform/) |
| MS Learn - Hosted Agents | [concepts](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents) |
| Deploy from private ACR | [how-to](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry) |
| CI/CD with azd | [how-to](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/set-up-ci-cd-cli) |
| Agent identity / RBAC | [how-to](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/manage-hosted-agent) |
