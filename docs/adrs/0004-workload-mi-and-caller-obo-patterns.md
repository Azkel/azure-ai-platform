# ADR 0004: Workload managed identity first; caller/OBO as an explicit second pattern

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-16 |
| **Labs** | [Hosted Agents](../../labs/hosted-agents/), [MCP on Azure](../../labs/mcp-on-azure/) |
| **Deciders** | Lab author |

## Context

AI workloads on Azure call PaaS (Storage, Key Vault, ...). Teams often reach for `DefaultAzureCredential` or a single app identity for every tool. That hides whether a call runs as the **platform** or as the **user**, and breaks teaching/audit stories (Acceler8it slides 7-8; Hosted Agents MI tools).

## Decision

1. **Default downstream access uses the workload managed identity** with least-privilege RBAC (e.g. Storage Blob Data Reader, Key Vault Secrets User).
2. **Caller-scoped access is a separate, named pattern** - token pass-through / OBO - implemented only in tools that intentionally act as the user.
3. **Do not mix both models in one tool.** Ingress auth ("who may call the host") is separate from tool auth ("whose Azure permissions apply").
4. **Avoid credential chains that steal MI** - e.g. MCP platform tools use `ManagedIdentityCredential` explicitly so OBO env vars cannot be picked up by `DefaultAzureCredential` / `EnvironmentCredential`.

## Consequences

- Clear demo narratives: list-as-app vs get-as-user (MCP); agent tools as MI (Hosted Agents).
- Slightly more code and Entra app setup when OBO is in scope (client secret, pre-authorized clients, dual RBAC).
- Operators must grant both MI roles and (when used) user data-plane roles.

## Alternatives considered

| Alternative | Why not |
|-------------|---------|
| Everything via user tokens | Breaks shared/platform tools; harder local smoke |
| Everything via MI | Cannot teach pass-through / audit of user data access |
| `DefaultAzureCredential` everywhere | Ambiguous identity in labs; env vars hijack MI |

## References

- [MCP architecture - two auth patterns](../../labs/mcp-on-azure/docs/architecture.md)
- Hosted Agents agent identity / RBAC in [labs/hosted-agents/docs/architecture.md](../../labs/hosted-agents/docs/architecture.md)
