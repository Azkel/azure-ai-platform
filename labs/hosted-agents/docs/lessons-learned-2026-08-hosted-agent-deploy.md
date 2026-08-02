# Lessons Learned: Hosted Agent CI/CD and Invoke (2026-08)

Working notes from bringing the HelloWorld hosted agent through GitHub Actions deploy to a usable invoke path (CLI + Foundry portal sandbox). Use this when hardening the lab or onboarding the next operator.

## Context

- Lab: `labs/hosted-agents`
- Branch work centered on `hosted-agents-permissions-fix`
- Infra: Terraform (`platform-core` + lab ACR/KV/project)
- Deploy: GitHub Actions → ACR build/push → `azd deploy`
- Client: `labs/hosted-agents/src/hosted-agent-client`

---

## What worked (durable fixes)

### 1. azd project / environment must exist in CI

**Symptom:** `azd env set` failed with `ERROR: no project exists; to create a new project, run azd init`.

**Cause:** Workflow ran `azd` from the repo root (no `azure.yaml`). Even in `labs/hosted-agents/src`, `.azure/` is gitignored, so clean CI has no environment.

**Fix:** Run azd steps with `working-directory: labs/hosted-agents/src`. If `.azure/<env>` is missing, `azd env new <env>`; otherwise `azd env select`. Then set Foundry-related env values.

### 2. GitHub workflow YAML must stay valid

**Symptom:** UI error *“Workflow does not exist or does not have a workflow_dispatch trigger in this branch.”*

**Cause:** Deploy step used a Python heredoc with **column-0** lines (`import yaml`, etc.). That breaks YAML parsing; GitHub then ignores the workflow on that branch.

**Fix:** Indent the heredoc body with the rest of the `run: |` block. Column-0 content inside `|` is invalid YAML even if the shell would accept it after strip.

### 3. `FOUNDRY_PROJECT_ENDPOINT` must be in the azd environment

**Symptom:** `azd deploy` failed: `FOUNDRY_PROJECT_ENDPOINT is required: environment variable was not found in the current azd environment`.

**Cause:** `azd ai project set` writes **global** azd config. `azd deploy` (in-project) reads the **active azd env** (`.azure/<env>/.env`).

**Fix:** Also `azd env set FOUNDRY_PROJECT_ENDPOINT …` (and related IDs/model name). Exporting to `$GITHUB_ENV` alone is not enough for azd.

### 4. Foundry DNS host ≠ Cognitive Account resource name

**Symptom:** `dial tcp: lookup cog-hosted-agents-dev-plc.services.ai.azure.com … no such host`.

**Cause:** Workflow built the URL from the **resource name** (`cog-hosted-agents-…`). Azure DNS uses **`custom_subdomain_name`** (`hosted-agents-…`, no `cog-` prefix).

**Correct project endpoint shape:**

```text
https://{customSubDomain}.services.ai.azure.com/api/projects/{projectName}
```

**Not:**

```text
https://{accountResourceName}.services.ai.azure.com/...
https://{customSubDomain}.cognitiveservices.azure.com/projects/...   # wrong for hosted-agent invoke
```

**Fix:** Look up `properties.customSubDomainName` (and optionally `properties.endpoint`) via Azure CLI in the workflow; do not invent the hostname from the `cog-` resource name.

Client setup scripts (`setup-appsettings.sh` / `.ps1`) had the same bug and were aligned to `services.ai.azure.com/api/projects/…`.

### 5. ACR pull rights for Foundry identities

**Symptom:** Deploy failed with `[ImageError] Container registry authentication failed` / AcrPull guidance.

**Cause:** Project (and often account) managed identity lacked pull roles; ACR may also need `authentication-as-arm` enabled for Foundry’s ARM-audience token exchange.

**Fix (IaC + CI belt-and-suspenders):**

- Enable ACR `azureADAuthenticationAsArmPolicy`
- Grant project + account MIs `AcrPull` and `Container Registry Repository Reader`
- Workflow step can assign/enable if Terraform has not been re-applied yet (with a short RBAC wait)

### 6. App Insights connection string via Key Vault

**Approach taken:**

- Terraform stores `applicationinsights-connection-string` in lab Key Vault
- Grant Foundry MIs `Key Vault Secrets User`
- At deploy time, workflow reads the secret (seeds from App Insights if missing) → `azd env set APPLICATIONINSIGHTS_CONNECTION_STRING`
- `azure.yaml` maps `${APPLICATIONINSIGHTS_CONNECTION_STRING}` into the agent

**Note:** Hosted agents do **not** support App Service-style `@Microsoft.KeyVault(...)` references in env. KV as source of truth + deploy-time resolution is the pragmatic lab pattern. Foundry “BYO Key Vault connection” is a heavier, first-connection-only path.

### 7. Interactive invoke needs Foundry data-plane RBAC

**Symptom:** CLI/portal-looking 404; Cognitiveservices host returned 403 lacking `AIServices/agents/read` / `agents/write`.

**Cause:** Subscription **Owner** does **not** grant Foundry agent dataActions. Only the deploy SP had **Foundry User**.

**Fix:** Assign **Foundry User** (and in practice **Azure AI Developer** helped LIST) to the interactive user on the Foundry account/project. Terraform gained `additional_foundry_user_principal_ids` for this.

**Misleading API behavior:** On `*.services.ai.azure.com`, missing data-plane permission often surfaces as **404 `Project not found`**, not 403.

---

## What did not work / still open

### A. Client still could not invoke after URL + RBAC fixes

After correcting the endpoint and granting Foundry User / Azure AI Developer:

- `GET` / `LIST` agents: **200** (agent present, versions `status: active`)
- `POST …/endpoint/protocols/openai/responses`: still **404 `Project not found`**
- Foundry portal **Test environment** showed the same **Error Project not found**

So the failure is **not** limited to the local CLI client.

### B. “No model deployed” was a red herring for Project not found

- Account had `gpt-5-mini`; agent env pointed at `gpt-5.4-mini` (later deployed by the operator).
- Missing/mismatched model would typically fail **inside** the container after invoke reaches it.
- It does **not** explain control-plane **Project not found** on the invoke route.

### C. Empty capabilityHosts correlated with broken invoke

Observed on the live subscription:

- Project + account `capabilityHosts` collections: **empty**
- Agent version had `protocol_versions: [responses/2.0.0]` but `container_protocol_versions: []`
- Local azd env had `ENABLE_CAPABILITY_HOST=false` (expected for Basic hosted-agent init per Foundry skills docs)

Terraform **now** includes:

- `foundry_agent_network_injection_enabled = true` (`network_injection.scenario = agent` on account create)
- Project capability host `caphost` (`capabilityHostKind = Agents`)

**Critical constraint (from docs / code comments):** agent **network injection must be present at Foundry account creation**. Adding it later is unsupported and is a known path to invoke returning **Project not found**.

**Implication for the current lab environment:** if `cog-hosted-agents-dev-plc` was created **before** network injection was enabled in Terraform, a **recreate** of the Foundry account (and dependent project/agent deploy) is likely required—not only `terraform apply` of the new capability-host resource.

Creating a minimal project capability host via REST was attempted from the agent environment but **could not be verified** here (sandbox proxy / DNS failures). Operators should confirm live `properties.networkInjections` and capabilityHosts with Azure CLI/portal.

### D. Tooling limitations during diagnosis

- Cursor agent sandbox often injects an HTTP proxy that returns **403 on CONNECT** to Azure endpoints, or DNS fails when proxy is unset.
- Long-running `az`/curl Task agents hung or were aborted.
- Prefer running verification commands in a local authenticated shell when iterating on Foundry data-plane issues.

---

## Decision log (short)

| Topic | Decision |
|-------|----------|
| CI azd cwd | Always `labs/hosted-agents/src` |
| Foundry endpoint construction | From `customSubDomainName` + `/api/projects/{name}` |
| Secrets for App Insights | Key Vault secret + deploy-time `azd env set` |
| ACR for hosted agents | Auth-as-ARM + pull roles on project/account MI |
| Interactive users | Explicit Foundry User (Owner insufficient) |
| Persistent Project not found | Treat as account/project runtime wiring (network injection / capability host); likely needs account recreate if injection missing at birth |

---

## Operator checklist (next time)

1. Confirm Foundry account `properties.networkInjections` includes `scenario: agent` (if using BYO VNet injection path).
2. Confirm project capability host exists (`…/capabilityHosts`).
3. Confirm custom subdomain hostname resolves (`{subdomain}.services.ai.azure.com`).
4. Confirm interactive identity has Foundry User (or equivalent) on account/project.
5. Confirm ACR auth-as-ARM + MI pull roles.
6. Confirm model deployment name matches `AZURE_AI_MODEL_DEPLOYMENT_NAME`.
7. Only then debug the client; portal sandbox is the ground truth for “can invoke?”.

---

## Useful verification commands

```bash
# Account network injection
az cognitiveservices account show \
  -n cog-hosted-agents-dev-plc -g rg-hosted-agents-dev-plc \
  --query "properties.networkInjections" -o json

# Capability hosts
SUB=$(az account show --query id -o tsv)
az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-hosted-agents-dev-plc/providers/Microsoft.CognitiveServices/accounts/cog-hosted-agents-dev-plc/projects/hosted-agents-project/capabilityHosts?api-version=2025-06-01"

# Data-plane list vs invoke
TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)
BASE="https://hosted-agents-dev-plc.services.ai.azure.com/api/projects/hosted-agents-project"
curl -sS -H "Authorization: Bearer $TOKEN" "$BASE/agents?api-version=v1"
curl -sS -w "\nHTTP:%{http_code}\n" -X POST \
  "$BASE/agents/hello-world-dotnet-responses/endpoint/protocols/openai/responses?api-version=v1" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"input":"Hi","store":true,"stream":false}'
```

---

## References

- [Hosted agent permissions](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agent-permissions)
- [Configure hosted agent env vars](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/configure-hosted-agent-env-variables)
- [Private networking / Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/virtual-networks)
- [Capability hosts](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/capability-hosts)
- [Foundry RBAC](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry)
- Q&A pattern: Terraform-created Foundry projects returning “project does not exist” until portal-equivalent wiring exists
