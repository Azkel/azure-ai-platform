# ADR 0005: Private Endpoint to tool targets; read-only first

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-16 |
| **Labs** | [Hosted Agents](../../labs/hosted-agents/), [MCP on Azure](../../labs/mcp-on-azure/) |
| **Deciders** | Lab author |

## Context

An MCP server or hosted agent that can reach Azure data over the public internet becomes a shortcut around network controls. Talk and lab claims ("controlled path to resources") need at least one real private path, without deploying the full PE grid from a reference diagram.

## Decision

1. **Tool targets used in the demo path should be reachable via Private Endpoint** (or equivalent private connectivity) from the workload network - not "public Storage + hope nobody finds the endpoint."
2. **v1 tools are read-only** (list/get/read secret). Write/delete tools wait until ingress and identity are proven.
3. **One teaching target is enough for Slice 1** (MCP: Storage; Hosted Agents: Storage + Key Vault as needed). Extra PE SKUs (SQL, App Service, "internal API") stay documentation/talk cues unless a lab explicitly needs them.
4. **Public network access on those accounts is disabled or tightly restricted** once PE is in place (lab Terraform owns the exact toggle).

## Consequences

- Labs need VNet integration for the compute host (CAE subnet, Foundry/agent networking as applicable).
- DNS / PE plumbing is part of the happy path; destroy/recreate must tolerate storage name reservation.
- Diagram honesty: talk may show more PE boxes than the lab deploys ([MCP Slice 1 vs talk](../../labs/mcp-on-azure/docs/architecture.md)).

## Alternatives considered

| Alternative | Why not |
|-------------|---------|
| Public PaaS endpoints for simplicity | Undercuts the isolation claim |
| Full PE grid in v1 | Cost/complexity; rejected in ADR 0001 |
| Write tools in v1 | Increases blast radius before the pattern is proven |

## References

- [ADR 0001](./0001-reference-baseline-and-vertical-slice-scope.md)
- MCP `terraform/storage.tf` / Hosted Agents storage + KV networking
