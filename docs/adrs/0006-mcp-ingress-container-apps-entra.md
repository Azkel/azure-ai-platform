# ADR 0006: MCP ingress - Container Apps + Entra (JWT / PRM), not Front Door or APIM in v1

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-16 |
| **Lab** | [MCP on Azure](../../labs/mcp-on-azure/) |
| **Deciders** | Lab author |

## Context

Acceler8it slide 10 may show **Front Door + WAF** in front of MCP. App Service has preview helpers for MCP Protected Resource Metadata; Container Apps Easy Auth does **not** emit RFC 9728 PRM on its own. The lab still needs Entra-authenticated HTTP MCP that VS Code can discover via OAuth.

## Decision

1. **v1 ingress binding is Container Apps + Microsoft Entra** (app registration, JWT bearer validation in the app).
2. **Front Door + WAF and APIM are deferred** - same *controlled ingress* concern, different SKU; document as omit vs talk diagram.
3. **Easy Auth stays enabled but `AllowAnonymous`** so unauthenticated `/mcp` reaches the app; the app returns `401` with `WWW-Authenticate` + `resource_metadata`, and serves `/.well-known/oauth-protected-resource`.
4. **Landing, health, and PRM paths stay anonymous**; `/mcp` requires a valid Bearer token (audience/scope aligned with HTTPS Application ID URI when custom domain is used).
5. **Pre-authorize lab clients** (Azure CLI, VS Code) on the API scope for demo and interactive login.

## Consequences

- Lower fixed cost and fewer moving parts than Front Door/APIM for a public self-deploy lab.
- Talk Q&A must say "Front Door is the edge hardening path; we bound the concern to CA+Entra."
- ACA Easy Auth alone is insufficient for MCP OAuth discovery - PRM is app-owned until the platform catches up.

## Alternatives considered

| Alternative | Why not for v1 |
|-------------|----------------|
| Front Door + WAF in front of CA | Better diagram parity; higher cost/ops - optional track |
| APIM as the only front door | Powerful policies; overkill for Slice 1 teaching |
| Easy Auth `Return401` only | Blocks custom WWW-Authenticate / PRM challenge for MCP clients |
| App Service host for built-in MCP PRM | Wrong runtime choice for the CA-focused talk path |

## References

- [MCP how to run - auth](../../labs/mcp-on-azure/docs/run.md)
- [MCP design - trade-offs](../../labs/mcp-on-azure/docs/design.md)
- [ADR 0001](./0001-reference-baseline-and-vertical-slice-scope.md)
