# ADR 0002: GitHub OIDC and remote Terraform state

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-16 |
| **Labs** | [Hosted Agents](../../labs/hosted-agents/), [MCP on Azure](../../labs/mcp-on-azure/) |
| **Deciders** | Lab author |

## Context

Public labs need a deploy/teardown path that works for the author and for GitHub Actions without checking secrets into the repo or relying on long-lived service-principal passwords. Both labs already use Azure Blob remote state and GitHub OIDC in practice (`docs/github/github-oidc-setup.md`, `docs/infrastructure/terraform-backend-setup.md`).

## Decision

1. **Authenticate CI with GitHub OIDC** (`azure/login` + Terraform `use_oidc`) - no long-lived client secrets for deploy/destroy workflows.
2. **Store Terraform state in a shared Azure Blob backend** (Azure AD auth to storage; keys disabled), configured via `TF_STATE_*` / `-backend-config`.
3. **Prefer workflow-driven apply/destroy** as the supported path for shared environments; local apply is allowed for bring-your-own subscriptions when the operator supplies the same backend pattern.
4. **Schedule or document teardown** (e.g. nightly destroy) so forgotten lab stacks do not accrue cost.

## Consequences

- Setup cost: one Entra app registration federated to GitHub, RBAC on subscription + state storage, documented secrets on the `dev` environment.
- Local developers still need Azure CLI / OIDC-capable identity; human `azd` paths may lack roles that the Actions deployer has (seen on Hosted Agents).
- Remote state must be shared for CI destroy to see stacks created locally - migrate local state before relying on workflow **down**.

## Alternatives considered

| Alternative | Why not |
|-------------|---------|
| SP client secret in GitHub Actions secrets | Rotation burden; broader leak blast radius |
| Local-only Terraform (no remote state) | Breaks CI teardown and multi-machine continuity |
| Access-key auth to state storage | Weaker than Azure AD; keys are another secret |

## References

- [GitHub OIDC setup](../github/github-oidc-setup.md)
- [Terraform backend setup](../infrastructure/terraform-backend-setup.md)
- Hosted Agents / MCP GitHub workflows under `.github/workflows/`
