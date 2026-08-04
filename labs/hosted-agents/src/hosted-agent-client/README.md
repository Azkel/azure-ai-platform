# Hosted Agent CLI Client (Dotnet)

A simple interactive CLI client for connecting to Azure AI Foundry Hosted Agents from your local machine.

## Features

- **Interactive chat** with hosted agents
- **Persistent session** - keeps HTTP client and Azure credentials cached
- **Token caching** - reuses Azure access tokens to avoid repeated authentication
- **Multiple configuration sources** - command line, environment variables, or appsettings.json
- **Clear screen command** - type `clear` to start fresh
- **Help command** - type `help` or `?` for available commands
- **Color-coded output** - errors in red, timing info in gray

## Quick Start

### 1. Navigate to the client directory

```bash
cd labs/hosted-agents/src/hosted-agent-client
```

### 2. Restore dependencies

```bash
dotnet restore
```

### 3. Configure (choose one method)

**Method A: Using setup script (Recommended)**

Use the provided setup script to automatically populate appsettings.json from your Azure resources:

```bash
# Run the setup script (requires az login)
./setup-appsettings.sh

# Or with custom project/agent names
./setup-appsettings.sh -p my-project -a my-agent

# Then run the client
dotnet run
```

For Windows (PowerShell):
```powershell
.\setup-appsettings.ps1
.\setup-appsettings.ps1 -ProjectName my-project -AgentName my-agent
```

**Method B: Manual appsettings.json (for advanced users)**

```bash
# Edit appsettings.json with your settings
cat > appsettings.json << EOF
{
  "FoundrySettings": {
    "Endpoint": "https://hosted-agents-dev-weu.services.ai.azure.com/api/projects/hosted-agents-project",
    "AgentName": "storage-kv-agent"
  }
}
EOF

# Then simply run (no arguments needed)
dotnet run
```

**Method B: Using environment variables**

```bash
export FOUNDRY_ENDPOINT="https://cog-*.services.ai.azure.com/api/projects/my-project"
export AGENT_NAME="storage-kv-agent"
dotnet run
```

**Method C: Using command line arguments**

```bash
dotnet run https://hosted-agents-dev-weu.services.ai.azure.com/api/projects/hosted-agents-project

# Or with both endpoint and agent name
dotnet run https://hosted-agents-dev-weu.services.ai.azure.com/api/projects/hosted-agents-project storage-kv-agent
```

## Configuration

The client supports multiple configuration methods with the following precedence (highest to lowest):

1. **Command line arguments** - `dotnet run <endpoint> [agent]`
2. **Environment variables** - `FOUNDRY_ENDPOINT`, `AGENT_NAME`
3. **appsettings.json** - Configuration file
4. **Defaults** - Agent name defaults to `storage-kv-agent`

### appsettings.json Format

```json
{
  "FoundrySettings": {
    "Endpoint": "https://hosted-agents-dev-weu.services.ai.azure.com/api/projects/hosted-agents-project",
    "AgentName": "storage-kv-agent"
  }
}
```

Place the `appsettings.json` file in the project directory (alongside Program.cs).

## Usage

```
Connected to:
  Endpoint: https://hosted-agents-dev-weu.services.ai.azure.com/api/projects/hosted-agents-project/agents/storage-kv-agent/endpoint/protocols/openai/responses?api-version=v1
  Agent:    storage-kv-agent

Type your messages below. Type 'exit', 'quit', 'q', or 'bye' to end.
Type 'help' or '?' for available commands.

You: Hello!
Agent: Hello! How can I help you today?
  Response time: 0.45s

You: What is Microsoft Foundry?
Agent: Microsoft Foundry is a platform for building... 
  Response time: 1.23s

You: help

Commands:
  exit, quit, q, bye  - Exit the chat
  help, ?          - Show this help
  clear            - Clear the screen

You: clear

  =============================================================
        Azure AI Foundry - Hosted Agent CLI Client
  =============================================================

Connected to:
  Endpoint: https://cog-*.services.ai.azure.com/...
  Agent:    storage-kv-agent

You: exit

Goodbye!
```

## Example questions (Storage + Key Vault)

The client only calls the agent endpoint. Key Vault and Storage are accessed **inside the hosted agent** via managed-identity **function tools** (only when the model decides they are needed). Use prompts like these to exercise that path:

| Goal | Example prompt |
|------|----------------|
| No Azure I/O | `What is Microsoft Foundry?` (should answer without calling tools) |
| Key Vault | `What operator message is stored in Key Vault?` |
| Storage write | `Please save a note that says "lab checkpoint 1", then tell me the blob name.` |
| Storage list | `List the recent note blobs you can see.` |
| Both | `Read the Key Vault demo secret and list the recent note blobs.` |

**What a healthy reply looks like:** for tool prompts, the agent echoes the demo secret text (from `agent-demo-message`) and/or a blob path under `notes/…`. For ordinary Q&A, it should not invent blob names or claim it wrote a note.

**Confirm outside the chat** (optional ground truth). The setup scripts grant your signed-in identity **Key Vault Secrets User** and **Storage Blob Data Contributor** so these work after RBAC propagates:

```bash
# Secret the agent should have read
az keyvault secret show \
  --vault-name kv-hosted-agents-dev-weu \
  --name agent-demo-message \
  --query value -o tsv

# Blobs created by recent turns
az storage blob list \
  --account-name sthostedagentsdevweu#### \
  --container-name agent-notes \
  --auth-mode login \
  --prefix notes/ \
  -o table
```

If the reply mentions `(unavailable: …)` or you get Storage/KV 403s in agent logs, check that the Docker deploy workflow granted the agent instance identity **Storage Blob Data Contributor** and **Key Vault Secrets User**.

## Command Line Arguments

| Argument | Description |
|----------|-------------|
| `<endpoint>` | Foundry project endpoint URL (required if FOUNDRY_ENDPOINT not set) |
| `[agent]` | Agent name (default: storage-kv-agent, or from AGENT_NAME env var) |


## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `FOUNDRY_ENDPOINT` | Foundry project endpoint URL | `https://hosted-agents-dev-weu.services.ai.azure.com/api/projects/hosted-agents-project` |
| `AGENT_NAME` | Agent name | `storage-kv-agent` |
| `AZURE_TENANT_ID` | Azure AD Tenant ID | From Azure CLI |
| `AZURE_CLIENT_ID` | Azure AD Application ID | From Azure CLI |
| `AZURE_CLIENT_SECRET` | Azure AD Application Secret | From Azure CLI |

## Authentication

The client uses `DefaultAzureCredential` from Azure.Identity package, which automatically tries multiple authentication methods in this order:

1. Environment variables (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET)
2. Managed Identity (when running on Azure)
3. Azure CLI credentials (`az login`)
4. Azure PowerShell
5. Visual Studio Code
6. Interactive browser

**For local development:**
Simply run `az login` before using the client, and it will automatically use your CLI credentials.

## Building

```bash
# Build the project
dotnet build

# Run without building first (auto-builds)
dotnet run https://hosted-agents-dev-weu.services.ai.azure.com/api/projects/hosted-agents-project
```

## Dependencies

- .NET 10 SDK
- Azure.Identity (NuGet package) - for Azure authentication
- DotNetEnv (NuGet package) - for .env file support (optional)

## Setup Scripts

The project includes helper scripts to automate configuration:

- **`setup-appsettings.sh`** - Bash script for Linux/macOS
- **`setup-appsettings.ps1`** - PowerShell script for Windows

Both scripts:
- Require Azure CLI to be installed and logged in (`az login`)
- Automatically detect your Foundry resource
- Populate appsettings.json with the correct endpoint
- Grant RBAC to the signed-in identity if missing:
  - **Foundry User** on the Foundry account (`agents/write` / client invoke; Owner alone is not enough)
  - **Key Vault Secrets User** on the lab Key Vault (read `agent-demo-message` for ground truth)
  - **Storage Blob Data Contributor** on the lab Storage Account (list/read note blobs)
- Support custom project, agent, Key Vault, and Storage names via command-line arguments

The RBAC step requires permission to create role assignments (Owner or Role Based Access Control Administrator on the account or resource group).

## Project Structure

```
hosted-agent-client/
├── Program.cs              # Main CLI application
├── HostedAgentClient.csproj  # .NET project file
├── appsettings.json        # Configuration file
├── setup-appsettings.sh    # Setup script (Linux/macOS)
├── setup-appsettings.ps1   # Setup script (Windows)
└── README.md               # This file
```

## Exit Commands

While in the interactive chat, type any of these to exit:
- `exit`
- `quit`

Or press `Ctrl+C` to exit immediately.

## Error Handling

If an error occurs during a request, the client will display the error message and continue, allowing you to retry or send a different message. Press `Ctrl+C` to exit on error.

## Session Management

The client maintains:
- A single `HttpClient` instance for connection reuse
- Cached Azure access token (refreshed automatically when expired)
- Persistent session across multiple messages

This means you don't need to re-authenticate for each message, and connections are reused for efficiency.
