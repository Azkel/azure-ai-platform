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

**Method A: Using appsettings.json (Recommended for demos)**

```bash
# Edit appsettings.json with your settings
cat > appsettings.json << EOF
{
  "FoundrySettings": {
    "Endpoint": "https://cog-*.services.ai.azure.com/api/projects/my-project",
    "AgentName": "hello-world-dotnet-responses"
  }
}
EOF

# Then simply run (no arguments needed)
dotnet run
```

**Method B: Using environment variables**

```bash
export FOUNDRY_ENDPOINT="https://cog-*.services.ai.azure.com/api/projects/my-project"
export AGENT_NAME="hello-world-dotnet-responses"
dotnet run
```

**Method C: Using command line arguments**

```bash
dotnet run https://cog-*.services.ai.azure.com/api/projects/my-project

# Or with both endpoint and agent name
dotnet run https://cog-*.services.ai.azure.com/api/projects/my-project hello-world-dotnet-responses
```

## Configuration

The client supports multiple configuration methods with the following precedence (highest to lowest):

1. **Command line arguments** - `dotnet run <endpoint> [agent]`
2. **Environment variables** - `FOUNDRY_ENDPOINT`, `AGENT_NAME`
3. **appsettings.json** - Configuration file
4. **Defaults** - Agent name defaults to `hello-world-dotnet-responses`

### appsettings.json Format

```json
{
  "FoundrySettings": {
    "Endpoint": "https://cog-*.services.ai.azure.com/api/projects/my-project",
    "AgentName": "hello-world-dotnet-responses"
  }
}
```

Place the `appsettings.json` file in the project directory (alongside Program.cs).

## Usage

```
Connected to:
  Endpoint: https://cog-*.services.ai.azure.com/api/projects/my-project/agents/hello-world-dotnet-responses/endpoint/protocols/openai/responses?api-version=v1
  Agent:    hello-world-dotnet-responses

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
  Agent:    hello-world-dotnet-responses

You: exit

Goodbye!
```

## Command Line Arguments

| Argument | Description |
|----------|-------------|
| `<endpoint>` | Foundry project endpoint URL (required if FOUNDRY_ENDPOINT not set) |
| `[agent]` | Agent name (default: hello-world-dotnet-responses, or from AGENT_NAME env var) |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `FOUNDRY_ENDPOINT` | Foundry project endpoint URL | Required |
| `AGENT_NAME` | Agent name | hello-world-dotnet-responses |
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
dotnet run <endpoint>
```

## Dependencies

- .NET 10 SDK
- Azure.Identity (NuGet package) - for Azure authentication
- DotNetEnv (NuGet package) - for .env file support (optional)

## Project Structure

```
hosted-agent-client/
├── Program.cs          # Main CLI application
├── HostedAgentClient.csproj  # .NET project file
└── README.md           # This file
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
