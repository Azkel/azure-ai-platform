# Hosted Agents - Storage + Key Vault Sample

BYO Responses agent for Azure AI Foundry that demonstrates managed-identity access to Azure Storage and Key Vault via function tools.

## Files

- `azure.yaml` - Azure Developer CLI configuration (env vars for model, storage, Key Vault)
- `AGENTS.md` - Coding agent instructions
- `storage-kv-agent/` - C# sample agent
  - `Program.cs` - Responses handler with Blob + SecretClient integration
  - `StorageKvAgent.csproj` - .NET project file
  - `Dockerfile` - Container build configuration
  - `.env.example` - Environment variable template
  - `.dockerignore` - Docker ignore patterns
  - `.azdignore` - Azure Developer CLI ignore patterns
- `hosted-agent-client/` - Simple .NET client to invoke the deployed agent

## Runtime behavior

1. Foundry Responses API is called with function tools registered:
   - `get_demo_secret` — `SecretClient` reads the demo secret from Key Vault
   - `persist_note` — `BlobContainerClient` writes a note under `notes/`
   - `list_recent_notes` — lists recent blob names
2. A tool loop executes only the tools the model requests (ordinary Q&A skips Azure I/O)
3. The final model text is returned to the caller

All Azure auth uses `DefaultAzureCredential` (agent instance identity when hosted).
