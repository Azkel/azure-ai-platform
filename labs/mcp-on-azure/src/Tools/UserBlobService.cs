using Azure;
using Azure.Core;
using Azure.Identity;
using Azure.Storage.Blobs;
using McpOnAzure;

namespace McpOnAzure.Tools;

public sealed class UserBlobService(
    StorageOptions options,
    IHttpContextAccessor httpContextAccessor)
{
    public async Task<string> GetBlobAsync(string blobName, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(blobName))
            throw new ArgumentException("blobName is required.", nameof(blobName));

        var (containerName, name) = ParseBlobRef(blobName.Trim());
        var credential = CreateCallerCredential();
        var container = new BlobContainerClient(
            new Uri($"https://{options.AccountName}.blob.core.windows.net/{containerName}"),
            credential);

        var blob = container.GetBlobClient(name);
        try
        {
            if (!await blob.ExistsAsync(ct))
                return $"Blob '{containerName}/{name}' not found (or not visible to the caller).";

            var download = await blob.DownloadContentAsync(ct);
            return download.Value.Content.ToString();
        }
        catch (RequestFailedException ex) when (ex.Status is 403 or 401)
        {
            return $"Access denied for caller identity on '{containerName}/{name}' " +
                   $"(HTTP {ex.Status}). Expected for platform-only blobs — use platform_list_blobs " +
                   "to confirm the MI can still see it.";
        }
    }

    private (string Container, string Name) ParseBlobRef(string blobRef)
    {
        var slash = blobRef.IndexOf('/');
        if (slash <= 0 || slash >= blobRef.Length - 1)
            return (options.ContainerName, blobRef);

        return (blobRef[..slash], blobRef[(slash + 1)..]);
    }

    private TokenCredential CreateCallerCredential()
    {
        var http = httpContextAccessor.HttpContext;
        // Easy Auth forwards the AAD access token when client secret is configured.
        var accessToken =
            http?.Request.Headers["X-MS-TOKEN-AAD-ACCESS-TOKEN"].FirstOrDefault()
            ?? ExtractBearer(http?.Request.Headers.Authorization.ToString());

        if (!string.IsNullOrEmpty(accessToken))
        {
            var tenantId = Environment.GetEnvironmentVariable("MCP_ENTRA_TENANT_ID");
            var clientId = Environment.GetEnvironmentVariable("MCP_ENTRA_CLIENT_ID");
            var clientSecret = Environment.GetEnvironmentVariable("MCP_ENTRA_CLIENT_SECRET");

            if (!string.IsNullOrEmpty(tenantId) &&
                !string.IsNullOrEmpty(clientId) &&
                !string.IsNullOrEmpty(clientSecret))
            {
                return new OnBehalfOfCredential(
                    tenantId,
                    clientId,
                    clientSecret,
                    accessToken);
            }
        }

        throw new InvalidOperationException(
            "user_get_blob requires a caller access token and OBO configuration " +
            "(X-MS-TOKEN-AAD-ACCESS-TOKEN or Authorization Bearer, plus MCP_ENTRA_TENANT_ID / CLIENT_ID / CLIENT_SECRET).");
    }

    private static string? ExtractBearer(string? authorization)
    {
        if (string.IsNullOrEmpty(authorization) ||
            !authorization.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return null;
        return authorization["Bearer ".Length..].Trim();
    }
}
