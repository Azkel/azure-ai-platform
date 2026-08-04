# Hosted Agents - Storage + Key Vault Sample

Based on the Microsoft Foundry [bring-your-own HelloWorld](https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/csharp/hosted-agents/bring-your-own/responses/HelloWorld) Responses sample, extended to demonstrate managed-identity access to Azure Storage and Key Vault.

## Files

- `README.foundry-sample.md` - Original Foundry sample documentation
- `azure.yaml` - Azure Developer CLI configuration (env vars for model, storage, Key Vault)
- `AGENTS.md` - Coding agent instructions
- `CLAUDE.md` - Claude Code configuration
- `storage-kv-agent/` - C# sample agent
  - `Program.cs` - Responses handler with Blob + SecretClient integration
  - `StorageKvAgent.csproj` - .NET project file
  - `Dockerfile` - Container build configuration
  - `.env.example` - Environment variable template
  - `.dockerignore` - Docker ignore patterns
  - `.azdignore` - Azure Developer CLI ignore patterns
- `hosted-agent-client/` - Simple .NET client to invoke the deployed agent

## Runtime behavior

1. `SecretClient` reads the user-provided demo secret from Key Vault
2. `BlobContainerClient` writes a turn note under `notes/` and lists recent blobs
3. Foundry Responses API generates the reply with that context in instructions

All Azure auth uses `DefaultAzureCredential` (agent instance identity when hosted).
