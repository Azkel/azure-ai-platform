# Architecture Decision Records

Thin, durable decisions for Azure AI Platform Labs. How-to detail stays in lab `docs/` and `docs/github/` / `docs/infrastructure/`.

| ADR | Title | Scope |
|-----|-------|-------|
| [0001](./0001-reference-baseline-and-vertical-slice-scope.md) | Reference baseline and vertical slice scope | MCP (patterns apply broadly) |
| [0002](./0002-github-oidc-and-remote-terraform-state.md) | GitHub OIDC and remote Terraform state | Cross-lab |
| [0003](./0003-lab-terraform-module-strategy.md) | Lab Terraform module strategy (`platform-core` vs lab-local) | Cross-lab |
| [0004](./0004-workload-mi-and-caller-obo-patterns.md) | Workload MI first; caller/OBO as explicit second pattern | Cross-lab |
| [0005](./0005-private-endpoint-tool-targets-readonly.md) | Private Endpoint to tool targets; read-only first | Cross-lab |
| [0006](./0006-mcp-ingress-container-apps-entra.md) | MCP ingress - CA + Entra (JWT/PRM), not Front Door/APIM in v1 | MCP |
| [0007](./0007-one-mcp-process-two-tool-identity-groups.md) | One MCP process, two tool identity groups | MCP |

**Deferred until implemented:** Front Door+WAF, APIM front door, internal REST fixture, thinner shared modules extracted from MCP.
