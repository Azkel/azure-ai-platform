# Support ticket: Foundry Hosted Agents 404 Project not found (Poland Central)

**Title:** Foundry Hosted Agents data plane returns 404 `Project not found` while control plane and Assistants playground work (Poland Central)

**Severity:** A / B (blocked hosted-agent deploy; Assistants chat works)

**Subscription ID:** `f17b9739-a0fe-48e5-a5e6-0d4182ebd26d`  
**Tenant ID:** `b3477e68-228c-49e0-a25f-b35347526099`  
**Region:** Poland Central  
**Resource group:** `rg-hosted-agents-dev-plc`  
**AIServices account:** `cog-hosted-agents-dev-plc`  
**Custom subdomain:** `hosted-agents-dev-plc`  
**Project:** `hosted-agents-project`  
**Project ARM ID:**  
`/subscriptions/f17b9739-a0fe-48e5-a5e6-0d4182ebd26d/resourceGroups/rg-hosted-agents-dev-plc/providers/Microsoft.CognitiveServices/accounts/cog-hosted-agents-dev-plc/projects/hosted-agents-project`

## Summary

Microsoft Foundry (kind=`AIServices`) was recreated in Poland Central with agent network injection at account creation. Control-plane resources show `Succeeded`, classic Assistants Agents playground works, and model chat works. Hosted Agents APIs on `*.services.ai.azure.com/api/projects/{project}` consistently return **404 `Project not found`**, so `azd deploy` cannot create a hosted agent version.

## What works

- Account `provisioningState=Succeeded`, `publicNetworkAccess=Enabled`
- `properties.networkInjections` includes `scenario=agent` on subnet  
  `.../subnets/snet-hosted-agents-dev-plc-001` (delegated `Microsoft.App/environments`, SAL `legionservicelink` present)
- Account capability host `cog-hosted-agents-dev-plc@aml_aiagentservice` (`capabilityHostKind=Agents`, `Succeeded`, subnet set)
- Project capability host `caphost` (`capabilityHostKind=Agents`, `Succeeded`)
- Project exists in ARM; endpoints map includes  
  `AI Foundry API = https://hosted-agents-dev-plc.services.ai.azure.com/api/projects/hosted-agents-project`
- DNS resolves for `hosted-agents-dev-plc.services.ai.azure.com`
- Model inference works (Chat playground / chat completions)
- Classic Assistants Agents playground works with `gpt-5-mini`
- Interactive user has **Foundry User** + **Azure AI Developer** on the account

## What fails

```bash
TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)
BASE=https://hosted-agents-dev-plc.services.ai.azure.com/api/projects/hosted-agents-project

curl -sS -H "Authorization: Bearer $TOKEN" "$BASE/agents?api-version=v1"
# HTTP 404 {"error":{"code":"NotFound","message":"Project not found"}}

# Hosted agent create via azd:
# POST $BASE/agents/hello-world-dotnet-responses/versions
# RESPONSE 404 NotFound — Project not found
```

Also observed: OpenAI **deployment list** endpoints return `404 Resource not found`, while direct chat completions against a known deployment name succeed (400 only for wrong params). Classic Agents UI previously showed “No deployment exists” until a compatible model was selected.

## Timeline / recreate context

1. Original account became stuck (`provisioningState=Accepted`) after failed `capabilityHosts/write` (invalid resource name).
2. Forced delete via `az resource delete`, then soft-delete/purge races / MSI `FailedIdentityOperation` (“pending delete”).
3. Account recreated successfully with network injection at create (~2026-08-02 18:46–18:51 UTC).
4. Project + capability hosts created shortly after; all report `Succeeded`.
5. Data-plane project APIs still 404 hours later despite RBAC grants.

## Request

Please investigate why the Hosted Agents / project data plane does not resolve project `hosted-agents-project` for this AIServices account in Poland Central, despite successful ARM project + Agents capability hosts and working Assistants playground. Need root cause and fix so  
`POST /api/projects/{project}/agents/{name}/versions` succeeds.

## Useful correlation / IDs

- Account created: ~`2026-08-02T18:46:41Z`
- Account Agents capability host created/modified: ~`2026-08-02T18:46:48Z` / `18:49:35Z`
- Project capability host created/modified: ~`2026-08-02T18:50:30Z` / `18:51:02Z`
- Sample failed azd deploy create_agent call: ~`2026-08-02T19:05Z` (local), endpoint above

## Related lab notes

See also [lessons-learned-2026-08-hosted-agent-deploy.md](./lessons-learned-2026-08-hosted-agent-deploy.md).
