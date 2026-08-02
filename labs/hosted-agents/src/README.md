# Hosted Agents - HelloWorld Sample

The files in this directory are copied from the Microsoft Foundry samples repository.

**Source:** https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/csharp/hosted-agents/bring-your-own/responses/HelloWorld

This is a minimal "hello world" hosted agent using the **Bring Your Own** approach with the **Responses protocol** in C#.

## Files

- `README.foundry-sample.md` - Original sample documentation
- `azure.yaml` - Azure Developer CLI configuration
- `AGENTS.md` - Coding agent instructions
- `CLAUDE.md` - Claude Code configuration
- `src/hello-world-dotnet-responses/` - C# source code
  - `Program.cs` - Main agent handler
  - `HelloWorld.csproj` - .NET project file
  - `Dockerfile` - Container build configuration
  - `.env.example` - Environment variable template
  - `.dockerignore` - Docker ignore patterns
  - `.azdignore` - Azure Developer CLI ignore patterns
