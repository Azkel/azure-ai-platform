# ADR 0003: Lab Terraform module strategy (`platform-core` vs lab-local)

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-16 |
| **Labs** | [Hosted Agents](../../labs/hosted-agents/), [MCP on Azure](../../labs/mcp-on-azure/) |
| **Deciders** | Lab author |

## Context

The umbrella repo has `shared-modules/platform-core` used by Hosted Agents (Foundry account, networking, monitoring, etc.). MCP on Azure needs Container Apps + Entra + Storage PE **without** pulling Foundry into the stack. Forcing every lab through `platform-core` either bloats non-Foundry labs or freezes Foundry-specific assumptions into "shared" code.

## Decision

1. **`platform-core` is optional, not mandatory.** Use it when the lab's workload naturally sits on that module's surface (today: Foundry Hosted Agents).
2. **Lab-local Terraform is allowed** when shared modules would drag unrelated products (e.g. Foundry) or block a vertical slice. MCP on Azure is Foundry-free and lab-local.
3. **Keep naming and patterns aligned** across lab-local stacks (RG/VNet/CAE/Storage suffixes, tags, OIDC providers) so extraction into thinner shared modules remains possible later.
4. **Extract shared modules only after two labs need the same shape** - do not invent a full LZ module library up front (see [ADR 0001](./0001-reference-baseline-and-vertical-slice-scope.md)).

## Consequences

- Readers must check each lab's `terraform/` for the real dependency graph.
- Some duplication (VNet, LAW, ACR patterns) is accepted until a second non-Foundry lab justifies a thinner module.
- Hosted Agents stays the reference for "Foundry on platform-core"; MCP stays the reference for "CA workload without Foundry."

## Alternatives considered

| Alternative | Why not |
|-------------|---------|
| Always use `platform-core` | Couples MCP to Foundry; fights Slice 1 cost/simplicity |
| Always lab-local, delete shared modules | Throws away Hosted Agents investment; worse for Foundry labs |
| Big-bang shared LZ modules first | Blocks demos; contradicts vertical-slice ADR 0001 |

## References

- `shared-modules/platform-core`
- [Hosted Agents terraform](../../labs/hosted-agents/terraform/)
- [MCP on Azure terraform](../../labs/mcp-on-azure/terraform/)
