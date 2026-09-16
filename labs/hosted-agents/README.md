# Hosted Agents

Deploy **Azure AI Foundry Hosted Agents** the platform way: Terraform for the foundation, GitHub Actions for CI/CD, and a sample agent that reaches **Storage** and **Key Vault** with managed identity - no keys in the image.

**Status:** Demoable v1

```
User → Foundry Hosted Agent (storage-kv-agent)
              ├─ Responses API → model (e.g. gpt-5-mini)
              ├─ tools → Key Vault / Storage (agent instance MI)
              └─ telemetry → Application Insights
                    ↑ VNet-injected Foundry account
```

Not a production landing zone - one vertical slice you can deploy and tear down. Patterns transfer; this lab binds them to Foundry Agent Service + `platform-core`.

---

## Quick start

**Deploy (GitHub Actions):**

1. **Terraform Deploy - Hosted Agents** → `apply` (~10-15 min)
2. **Docker Build, Push and Deploy - Hosted Agents** → build + `azd` deploy + post-deploy RBAC (~5-10 min)
3. Smoke: `./demo.sh` from this directory (needs `az login` + live lab RG)

**Invoke after deploy** (needs `az login`):

```bash
TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)
FOUNDRY_ENDPOINT="https://hosted-agents-dev-weu.services.ai.azure.com/api/projects/hosted-agents-project"

curl -X POST "$FOUNDRY_ENDPOINT/agents/storage-kv-agent/endpoint/protocols/openai/responses?api-version=v1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"input": "What is the operator demo message in Key Vault?", "store": true, "stream": false}'
```

**Teardown:** workflow **Terraform Deploy - Hosted Agents** → `destroy`, or nightly cleanup at 21:00 UTC.

Region: **West Europe** (Hosted Agents data-plane verified there). Details in [docs/run.md](./docs/run.md).

---

## Docs (details live here)

| Doc | What's in it |
|-----|----------------|
| [Architecture](./docs/architecture.md) | Why this lab, sample agent, MI/RBAC timing, data flow |
| [How to run](./docs/run.md) | Prerequisites, Actions, Terraform, smoke, local test, troubleshooting |
| [Design notes](./docs/design.md) | Trade-offs, limitations, cost, cleanup quirks, when to use alternatives |
| [Terraform](./terraform/README.md) | Module wiring and variables |
| [Sample source](./src/README.md) | Agent + client layouts |

Repo ADRs: [index](../../docs/adrs/README.md) · [0002 OIDC/state](../../docs/adrs/0002-github-oidc-and-remote-terraform-state.md) · [0003 platform-core](../../docs/adrs/0003-lab-terraform-module-strategy.md) · [0004 MI patterns](../../docs/adrs/0004-workload-mi-and-caller-obo-patterns.md).

---

## Layout

```
labs/hosted-agents/
├── README.md       ← you are here
├── docs/           ← deeper pages
├── demo.sh         ← resolve RG + prove KV / Storage tools
├── terraform/
└── src/
    ├── storage-kv-agent/   ← .NET BYO Responses sample
    └── hosted-agent-client/
```

---

## License

MIT - see [`LICENSE`](../../LICENSE).
