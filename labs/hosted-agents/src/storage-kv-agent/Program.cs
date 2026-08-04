// Copyright (c) Microsoft. All rights reserved.

/*
 * Hosted agent — Bring Your Own Responses (C#) with Azure Storage + Key Vault
 *
 * Extends the Foundry HelloWorld BYO sample to demonstrate managed-identity
 * access to Azure resources from a hosted agent container via function tools:
 *
 *   - get_demo_secret   — read a user-provided demo message from Key Vault
 *   - persist_note      — write a note blob to Azure Storage
 *   - list_recent_notes — list recent note blob names
 *
 * The model calls these tools only when needed; ordinary Q&A does not hit
 * Storage or Key Vault.
 *
 * Authentication uses DefaultAzureCredential:
 *   - Hosted: agent instance identity (RBAC assigned post-deploy)
 *   - Local: Azure CLI / VS / env credentials with matching RBAC
 *
 * Required environment variables:
 *   FOUNDRY_PROJECT_ENDPOINT         — Foundry project endpoint (auto-injected when hosted)
 *   AZURE_AI_MODEL_DEPLOYMENT_NAME   — Model deployment name (azure.yaml)
 *   AZURE_STORAGE_ACCOUNT_NAME       — Storage account for note blobs
 *   AZURE_STORAGE_CONTAINER_NAME     — Blob container name (default: agent-notes)
 *   AZURE_KEY_VAULT_URI              — Key Vault URI
 *   AZURE_KEY_VAULT_SECRET_NAME      — Secret name for the user-provided demo message
 *
 * Usage:
 *   dotnet run
 *
 *   curl -sS -X POST http://localhost:8088/responses \
 *     -H "Content-Type: application/json" \
 *     -d '{"input": "What is Microsoft Foundry?", "stream": false}' | jq .
 */

using System.Text;
using System.Text.Json;
using Azure.AI.AgentServer.Responses;
using Azure.AI.AgentServer.Responses.Models;
using Azure.AI.Extensions.OpenAI;
using Azure.AI.Projects;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using DotNetEnv;
using Microsoft.Extensions.Logging;
using OpenAI.Responses;

Env.NoClobber().TraversePath().Load();

ResponsesServer.Run<AzureIntegrationHandler>(configure: builder =>
{
    if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_CONNECTION_STRING")))
        Console.Error.WriteLine(
            "[WARNING] APPLICATIONINSIGHTS_CONNECTION_STRING not set — traces will not be sent " +
            "to Application Insights. Set it to enable local telemetry. " +
            "(This variable is auto-injected in hosted Foundry containers — do not declare it in azure.yaml.)");

    var endpoint = Environment.GetEnvironmentVariable("FOUNDRY_PROJECT_ENDPOINT")
        ?? throw new InvalidOperationException(
            "FOUNDRY_PROJECT_ENDPOINT environment variable is not set.");

    var model = Environment.GetEnvironmentVariable("AZURE_AI_MODEL_DEPLOYMENT_NAME")
        ?? throw new InvalidOperationException(
            "AZURE_AI_MODEL_DEPLOYMENT_NAME environment variable is not set.");

    var storageAccount = Environment.GetEnvironmentVariable("AZURE_STORAGE_ACCOUNT_NAME")
        ?? throw new InvalidOperationException(
            "AZURE_STORAGE_ACCOUNT_NAME environment variable is not set.");

    var containerName = Environment.GetEnvironmentVariable("AZURE_STORAGE_CONTAINER_NAME")
        ?? "agent-notes";

    var keyVaultUri = Environment.GetEnvironmentVariable("AZURE_KEY_VAULT_URI")
        ?? throw new InvalidOperationException(
            "AZURE_KEY_VAULT_URI environment variable is not set.");

    var secretName = Environment.GetEnvironmentVariable("AZURE_KEY_VAULT_SECRET_NAME")
        ?? "agent-demo-message";

    var credential = new DefaultAzureCredential();

    var projectClient = new AIProjectClient(new Uri(endpoint), credential);
    var responsesClient = projectClient.ProjectOpenAIClient
        .GetProjectResponsesClientForModel(model);

    var blobServiceClient = new BlobServiceClient(
        new Uri($"https://{storageAccount}.blob.core.windows.net"),
        credential);
    var blobContainerClient = blobServiceClient.GetBlobContainerClient(containerName);

    var secretClient = new SecretClient(new Uri(keyVaultUri), credential);

    builder.Services.AddSingleton(responsesClient);
    builder.Services.AddSingleton(blobContainerClient);
    builder.Services.AddSingleton(secretClient);
    builder.Services.AddSingleton(new AgentAzureOptions(secretName));
});

/// <summary>Non-secret Azure integration settings resolved from environment.</summary>
public sealed record AgentAzureOptions(string DemoSecretName);

/// <summary>
/// Responses handler that exposes Key Vault and Storage as function tools
/// and runs a tool loop so the model invokes them only when needed.
/// </summary>
public sealed class AzureIntegrationHandler(
    ProjectResponsesClient responsesClient,
    BlobContainerClient blobContainerClient,
    SecretClient secretClient,
    AgentAzureOptions azureOptions,
    ILogger<AzureIntegrationHandler> logger) : ResponseHandler
{
    private const int MaxToolRounds = 5;

    private const string BaseSystemPrompt =
        "You are a helpful AI assistant for an Azure AI platform lab. Be concise and informative. " +
        "You have tools for Azure Key Vault and Azure Blob Storage via managed identity. " +
        "Call get_demo_secret only when the user asks about the operator/demo Key Vault message or configuration. " +
        "Call persist_note only when the user asks to save, remember, or persist something. " +
        "Call list_recent_notes only when the user asks about stored notes or recent blobs. " +
        "Do not call these tools for ordinary questions.";

    private static readonly ResponseTool GetDemoSecretTool = ResponseTool.CreateFunctionTool(
        functionName: "get_demo_secret",
        functionParameters: BinaryData.FromString("""
            {
              "type": "object",
              "properties": {},
              "additionalProperties": false
            }
            """),
        strictModeEnabled: true,
        functionDescription:
            "Read the operator-provided demo message from Azure Key Vault. " +
            "Use only when the user asks about the Key Vault demo secret or configuration message.");

    private static readonly ResponseTool PersistNoteTool = ResponseTool.CreateFunctionTool(
        functionName: "persist_note",
        functionParameters: BinaryData.FromString("""
            {
              "type": "object",
              "properties": {
                "content": {
                  "type": "string",
                  "description": "Text to store as a blob note under notes/."
                }
              },
              "required": ["content"],
              "additionalProperties": false
            }
            """),
        strictModeEnabled: true,
        functionDescription:
            "Persist a text note to Azure Blob Storage. " +
            "Use only when the user asks to save, remember, or persist content.");

    private static readonly ResponseTool ListRecentNotesTool = ResponseTool.CreateFunctionTool(
        functionName: "list_recent_notes",
        functionParameters: BinaryData.FromString("""
            {
              "type": "object",
              "properties": {},
              "additionalProperties": false
            }
            """),
        strictModeEnabled: true,
        functionDescription:
            "List the most recent note blob names in Azure Storage. " +
            "Use only when the user asks about stored notes or recent blobs.");

    public override IAsyncEnumerable<ResponseStreamEvent> CreateAsync(
        CreateResponse request,
        ResponseContext context,
        CancellationToken cancellationToken)
    {
        return new TextResponse(context, request,
            createText: ct => GenerateTextAsync(context, ct));
    }

    private async Task<string> GenerateTextAsync(
        ResponseContext context,
        CancellationToken cancellationToken)
    {
        var userInput = await context.GetInputTextAsync(cancellationToken: cancellationToken) ?? "Hello!";
        var history = await context.GetHistoryAsync(cancellationToken);

        logger.LogInformation("Processing request {ResponseId}", context.ResponseId);

        var options = new CreateResponseOptions
        {
            Instructions = BaseSystemPrompt,
            ParallelToolCallsEnabled = true,
        };
        options.Tools.Add(GetDemoSecretTool);
        options.Tools.Add(PersistNoteTool);
        options.Tools.Add(ListRecentNotesTool);

        foreach (var item in history)
        {
            if (item is OutputItemMessage { Content: { } contents })
            {
                foreach (var content in contents)
                {
                    switch (content)
                    {
                        case MessageContentOutputTextContent { Text: { } assistantText }:
                            options.InputItems.Add(ResponseItem.CreateAssistantMessageItem(assistantText));
                            break;
                        case MessageContentInputTextContent { Text: { } userText }:
                            options.InputItems.Add(ResponseItem.CreateUserMessageItem(userText));
                            break;
                    }
                }
            }
        }

        options.InputItems.Add(ResponseItem.CreateUserMessageItem(userInput));

        try
        {
            for (var round = 0; round < MaxToolRounds; round++)
            {
                var result = await responsesClient.CreateResponseAsync(options, cancellationToken);
                var response = result.Value;
                var functionCalls = response.OutputItems.OfType<FunctionCallResponseItem>().ToList();

                if (functionCalls.Count == 0)
                    return response.GetOutputText() ?? string.Empty;

                foreach (var outputItem in response.OutputItems)
                    options.InputItems.Add(outputItem);

                foreach (var call in functionCalls)
                {
                    logger.LogInformation(
                        "Tool call {FunctionName} (callId={CallId}) on response {ResponseId}",
                        call.FunctionName,
                        call.CallId,
                        context.ResponseId);

                    var toolOutput = await ExecuteToolAsync(
                        call,
                        context.ResponseId,
                        cancellationToken);

                    options.InputItems.Add(
                        ResponseItem.CreateFunctionCallOutputItem(call.CallId, toolOutput));
                }
            }

            logger.LogWarning(
                "Reached max tool rounds ({MaxRounds}) for response {ResponseId}",
                MaxToolRounds,
                context.ResponseId);
            return "I reached the tool-call limit before finishing. Please try a simpler request.";
        }
        catch (Exception ex)
        {
            logger.LogError(ex,
                "Foundry model call failed. Ensure deployment '{Model}' exists on the Foundry account and the agent identity can call it.",
                Environment.GetEnvironmentVariable("AZURE_AI_MODEL_DEPLOYMENT_NAME"));
            return
                "The Foundry model call failed. " +
                $"Check that model deployment '{Environment.GetEnvironmentVariable("AZURE_AI_MODEL_DEPLOYMENT_NAME")}' exists " +
                $"and is reachable. Details: {ex.GetType().Name}: {ex.Message}";
        }
    }

    private async Task<string> ExecuteToolAsync(
        FunctionCallResponseItem call,
        string responseId,
        CancellationToken cancellationToken)
    {
        try
        {
            return call.FunctionName switch
            {
                "get_demo_secret" => await GetDemoSecretAsync(cancellationToken),
                "persist_note" => await PersistNoteAsync(
                    responseId,
                    ExtractRequiredStringArg(call.FunctionArguments, "content"),
                    cancellationToken),
                "list_recent_notes" => FormatNoteList(
                    await ListRecentNoteNamesAsync(cancellationToken)),
                _ => $"Unknown tool '{call.FunctionName}'.",
            };
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Tool '{FunctionName}' failed", call.FunctionName);
            return $"Tool '{call.FunctionName}' failed: {ex.GetType().Name}: {ex.Message}";
        }
    }

    private static string ExtractRequiredStringArg(BinaryData arguments, string name)
    {
        using var doc = JsonDocument.Parse(arguments);
        if (!doc.RootElement.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(value.GetString()))
        {
            throw new ArgumentException($"Tool argument '{name}' is required.");
        }

        return value.GetString()!;
    }

    private static string FormatNoteList(IReadOnlyList<string> names) =>
        names.Count == 0
            ? "(no notes found)"
            : string.Join(", ", names);

    private async Task<string> GetDemoSecretAsync(CancellationToken cancellationToken)
    {
        try
        {
            KeyVaultSecret secret = await secretClient.GetSecretAsync(
                azureOptions.DemoSecretName,
                cancellationToken: cancellationToken);
            return secret.Value;
        }
        catch (Exception ex)
        {
            logger.LogError(ex,
                "Failed to read Key Vault secret '{SecretName}'. Ensure the agent identity has Key Vault Secrets User.",
                azureOptions.DemoSecretName);
            return $"(unavailable: could not read secret '{azureOptions.DemoSecretName}')";
        }
    }

    private async Task<string> PersistNoteAsync(
        string responseId,
        string noteContent,
        CancellationToken cancellationToken)
    {
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyyMMdd'T'HHmmssfff'Z'");
        var blobName = $"notes/{timestamp}-{SanitizeFileSegment(responseId)}.txt";
        var content = new StringBuilder()
            .AppendLine($"response_id: {responseId}")
            .AppendLine($"timestamp_utc: {DateTimeOffset.UtcNow:O}")
            .AppendLine("note:")
            .AppendLine(noteContent)
            .ToString();

        try
        {
            await blobContainerClient.CreateIfNotExistsAsync(
                PublicAccessType.None,
                cancellationToken: cancellationToken);

            var blobClient = blobContainerClient.GetBlobClient(blobName);
            await blobClient.UploadAsync(
                BinaryData.FromString(content),
                overwrite: true,
                cancellationToken: cancellationToken);

            return $"Wrote blob '{blobName}'.";
        }
        catch (Exception ex)
        {
            logger.LogError(ex,
                "Failed to write blob note. Ensure the agent identity has Storage Blob Data Contributor.");
            return "(unavailable: blob write failed)";
        }
    }

    private async Task<IReadOnlyList<string>> ListRecentNoteNamesAsync(CancellationToken cancellationToken)
    {
        try
        {
            var names = new List<string>();
            await foreach (var item in blobContainerClient.GetBlobsAsync(
                               traits: BlobTraits.None,
                               states: BlobStates.None,
                               prefix: "notes/",
                               cancellationToken: cancellationToken))
            {
                names.Add(item.Name);
            }

            return names
                .OrderByDescending(n => n, StringComparer.Ordinal)
                .Take(5)
                .ToList();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to list recent blob notes.");
            return ["(unavailable)"];
        }
    }

    private static string SanitizeFileSegment(string value)
    {
        var sb = new StringBuilder(value.Length);
        foreach (var ch in value)
        {
            sb.Append(char.IsLetterOrDigit(ch) || ch is '-' or '_' ? ch : '-');
        }

        return sb.ToString();
    }
}
