using Azure.Identity;
using Azure.Storage.Blobs;
using McpOnAzure;

namespace McpOnAzure.Tools;

public sealed class PlatformBlobService(StorageOptions options)
{
    // Explicit MI — do not use DefaultAzureCredential here: OBO env vars
    // (MCP_ENTRA_*) must not steal platform.* identity via EnvironmentCredential.
    private readonly BlobServiceClient _service = new(
        new Uri($"https://{options.AccountName}.blob.core.windows.net"),
        new ManagedIdentityCredential());

    private readonly string[] _containers =
    [
        options.ContainerName,
        options.PlatformOnlyContainerName,
    ];

    public async Task<string> ListBlobsAsync(CancellationToken ct)
    {
        try
        {
            var names = new List<string>();
            foreach (var containerName in _containers)
            {
                var container = _service.GetBlobContainerClient(containerName);
                await foreach (var item in container.GetBlobsAsync(cancellationToken: ct))
                {
                    names.Add($"{containerName}/{item.Name}");
                }
            }

            return names.Count == 0
                ? "(no blobs — seed the containers after apply)"
                : string.Join('\n', names);
        }
        catch (Exception ex)
        {
            return $"platform_list_blobs failed: {ex.GetType().Name}: {ex.Message}";
        }
    }
}
