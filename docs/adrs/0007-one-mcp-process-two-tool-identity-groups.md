# ADR 0007: One MCP process, two tool identity groups

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-16 |
| **Lab** | [MCP on Azure](../../labs/mcp-on-azure/) |
| **Deciders** | Lab author |

## Context

The Acceler8it narrative contrasts **platform credentials** vs **user credentials** for tools. That could be implemented as two servers, two Container Apps, or one process with two tool groups. The lab goal is the smallest demo that still makes the distinction obvious.

## Decision

1. **Ship a single .NET MCP server** (one Container App, one `/mcp` endpoint).
2. **Expose two tool groups on that server:**
   - `platform_*` - workload managed identity only
   - `user_*` - caller Bearer token → OBO to the tool target
3. **Use one Storage account with intentional RBAC asymmetry** (e.g. shared `mcp-demo` vs MI-only `mcp-platform-only`) so list-as-app vs get-as-user (and deny) is visible in one demo.
4. **Do not deploy a second "user MCP" app** for Slice 1.

## Consequences

- One URL for the meetup landing page and VS Code config.
- Clear teaching pair without doubling CA/Entra cost.
- Requires careful credential isolation in code ([ADR 0004](./0004-workload-mi-and-caller-obo-patterns.md)).
- Deeper Graph/OBO encyclopedia and multi-tenant ERP remain out of scope.

## Alternatives considered

| Alternative | Why not |
|-------------|---------|
| Two Container Apps (platform vs user) | Doubles ops; weaker "same server, different credentials" punchline |
| MI-only Slice 1, user tools later | Under-sells talk slides 7-8 for the follow-up lab |
| Per-tool microservices | Not a platform-hosting lab |

## References

- [MCP architecture](../../labs/mcp-on-azure/docs/architecture.md)
- [ADR 0004](./0004-workload-mi-and-caller-obo-patterns.md)
