# Coding Agent Instructions

This lab is a **Foundry hosted agent** — a containerized AI agent that runs in [Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents). The sample shows BYO Responses with on-demand Azure Storage and Key Vault access via managed identity.

## Key files

- `storage-kv-agent/Program.cs` — agent handler and function tools
- `storage-kv-agent/Dockerfile` — container definition
- `azure.yaml` — azd agent project configuration
- `hosted-agent-client/` — CLI client for invoking the deployed agent

## Development workflow

The **Azure Developer CLI (`azd`)** manages the local agent lifecycle from this directory:

```bash
azd ai agent run                           # Run locally on http://localhost:8088
azd ai agent invoke --local "your message" # Test the local agent
azd deploy                                 # Deploy to Foundry
azd ai agent invoke "your message"         # Invoke the deployed agent
```

Infrastructure (ACR, Storage, Key Vault, RBAC) is managed by Terraform under `../terraform/`. Container images are built and pushed by the repo GitHub Actions workflow.

## References

- [Hosted agents overview](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents)
- Lab docs: [`../README.md`](../README.md)
