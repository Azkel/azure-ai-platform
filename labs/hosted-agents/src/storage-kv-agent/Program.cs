// Copyright (c) Microsoft. All rights reserved.

/*
 * Hosted agent — Bring Your Own Responses (C#) with Azure Storage + Key Vault
 *
 * Extends the Foundry HelloWorld BYO sample to demonstrate managed-identity
 * access to Azure resources from a hosted agent container:
 *
 *   1. Read a user-provided demo message from Key Vault (SecretClient + MI)
 *   2. Persist each turn as a blob note (BlobContainerClient + MI)
 *   3. Forward the enriched prompt to a Foundry model via the Responses API
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
/// Responses handler that reads a Key Vault secret, writes a blob note, then calls the Foundry model.
/// </summary>
public sealed class AzureIntegrationHandler(
    ProjectResponsesClient responsesClient,
    BlobContainerClient blobContainerClient,
    SecretClient secretClient,
    AgentAzureOptions azureOptions,
    ILogger<AzureIntegrationHandler> logger) : ResponseHandler
{
    private const string BaseSystemPrompt =
        "You are a helpful AI assistant for an Azure AI platform lab. Be concise and informative. " +
        "When relevant, acknowledge that you can persist notes to Azure Storage and read configuration from Key Vault via managed identity.";

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

        var demoMessage = await GetDemoSecretAsync(cancellationToken);
        var blobName = await PersistNoteAsync(context.ResponseId, userInput, cancellationToken);
        var recentNotes = await ListRecentNoteNamesAsync(cancellationToken);

        logger.LogInformation(
            "Key Vault secret '{SecretName}' loaded; note written to blob '{BlobName}'",
            azureOptions.DemoSecretName,
            blobName);

        var instructions = new StringBuilder()
            .AppendLine(BaseSystemPrompt)
            .AppendLine()
            .AppendLine("Operator-provided Key Vault configuration (demo secret):")
            .AppendLine(demoMessage)
            .AppendLine()
            .AppendLine($"This turn was persisted to blob: {blobName}")
            .AppendLine($"Recent note blobs in the container: {string.Join(", ", recentNotes)}")
            .ToString();

        var options = new CreateResponseOptions
        {
            Instructions = instructions,
        };

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

        var result = await responsesClient.CreateResponseAsync(options, cancellationToken);
        return result.Value.GetOutputText() ?? string.Empty;
    }

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
        string userInput,
        CancellationToken cancellationToken)
    {
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyyMMdd'T'HHmmssfff'Z'");
        var blobName = $"notes/{timestamp}-{SanitizeFileSegment(responseId)}.txt";
        var content = new StringBuilder()
            .AppendLine($"response_id: {responseId}")
            .AppendLine($"timestamp_utc: {DateTimeOffset.UtcNow:O}")
            .AppendLine("user_input:")
            .AppendLine(userInput)
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

            return blobName;
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
