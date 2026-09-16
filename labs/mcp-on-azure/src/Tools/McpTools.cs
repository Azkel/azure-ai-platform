using System.ComponentModel;
using ModelContextProtocol.Server;

namespace McpOnAzure.Tools;

[McpServerToolType]
public static class PlatformTools
{
    [McpServerTool(Name = "platform_list_blobs"), Description(
        "List blobs in mcp-demo and mcp-platform-only using the MCP server managed identity (platform credentials). Names are container/blob.")]
    public static Task<string> ListBlobs(
        PlatformBlobService blobs,
        CancellationToken cancellationToken)
        => blobs.ListBlobsAsync(cancellationToken);
}

[McpServerToolType]
public static class UserTools
{
    [McpServerTool(Name = "user_get_blob"), Description(
        "Read a blob using the caller's identity (OBO), not the app managed identity. " +
        "Try hello.txt (allowed) vs mcp-platform-only/platform-only.txt (expect Access denied).")]
    public static Task<string> GetBlob(
        UserBlobService blobs,
        [Description("Blob ref: 'hello.txt' (demo container) or 'mcp-platform-only/platform-only.txt'")] string blobName,
        CancellationToken cancellationToken)
        => blobs.GetBlobAsync(blobName, cancellationToken);
}
