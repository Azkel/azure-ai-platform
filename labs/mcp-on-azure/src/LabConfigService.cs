using System.Text.Json;
using System.Text.Json.Serialization;

namespace McpOnAzure;

public interface ILabConfigService
{
    LabPublicConfig GetPublicConfig(HttpRequest request);
}

public sealed class LabConfigService(IConfiguration configuration) : ILabConfigService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    private static readonly string[] Tools =
    [
        "platform_list_blobs",
        "user_get_blob",
    ];

    public LabPublicConfig GetPublicConfig(HttpRequest request)
    {
        var baseUrl = ResolvePublicBaseUrl(request).TrimEnd('/');
        var mcpUrl = $"{baseUrl}/mcp";
        // Canonical resource for MCP OAuth (must match an Entra Application ID URI).
        var resource = FirstNonEmpty(
            configuration["MCP_ENTRA_RESOURCE"],
            Environment.GetEnvironmentVariable("MCP_ENTRA_RESOURCE"),
            mcpUrl)!;
        var tenantId = RequireConfig("MCP_ENTRA_TENANT_ID", fallback: "(not configured)");
        var scope = FirstNonEmpty(
            configuration["MCP_ENTRA_SCOPE"],
            Environment.GetEnvironmentVariable("MCP_ENTRA_SCOPE"),
            $"{resource}/access_as_user")!;
        var authorizationServer = tenantId is "(not configured)"
            ? "https://login.microsoftonline.com/common/v2.0"
            : $"https://login.microsoftonline.com/{tenantId}/v2.0";

        return new LabPublicConfig(
            Lab: "mcp-on-azure",
            PublicBaseUrl: baseUrl,
            McpUrl: mcpUrl,
            Resource: resource,
            TenantId: tenantId,
            ClientId: RequireConfig("MCP_ENTRA_CLIENT_ID", fallback: "(not configured)"),
            Scope: scope,
            AuthorizationServer: authorizationServer,
            PrmUrl: $"{baseUrl}/.well-known/oauth-protected-resource",
            Tools: Tools,
            TokenCommand: $"az account get-access-token --scope \"{scope}\" --query accessToken -o tsv",
            VsCodeMcpJson: BuildVsCodeMcpJson(mcpUrl));
    }

    private string ResolvePublicBaseUrl(HttpRequest request)
    {
        var configured = FirstNonEmpty(
            configuration["MCP_PUBLIC_BASE_URL"],
            Environment.GetEnvironmentVariable("MCP_PUBLIC_BASE_URL"));

        if (configured is not null)
            return configured;

        // Container Apps terminates TLS at the edge; request.Scheme is often "http".
        var forwarded = request.Headers["X-Forwarded-Proto"].FirstOrDefault();
        var scheme = string.IsNullOrWhiteSpace(forwarded)
            ? request.Scheme
            : forwarded.Split(',')[0].Trim();

        if (!string.Equals(scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)
            && !request.Host.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase))
        {
            scheme = Uri.UriSchemeHttps;
        }

        return $"{scheme}://{request.Host.Value}";
    }

    private string RequireConfig(string key, string fallback) =>
        FirstNonEmpty(configuration[key], Environment.GetEnvironmentVariable(key)) ?? fallback;

    private static string? FirstNonEmpty(params string?[] values)
    {
        foreach (var value in values)
        {
            if (!string.IsNullOrWhiteSpace(value))
                return value.Trim();
        }

        return null;
    }

    private static string BuildVsCodeMcpJson(string mcpUrl)
    {
        // Interactive OAuth: VS Code discovers PRM from 401 WWW-Authenticate / well-known.
        var document = new VsCodeMcpDocument(
            Servers: new Dictionary<string, VsCodeMcpServer>
            {
                ["mcp-on-azure"] = new(Type: "http", Url: mcpUrl),
            });

        return JsonSerializer.Serialize(document, JsonOptions);
    }

    private sealed record VsCodeMcpDocument(
        [property: JsonPropertyName("servers")] IReadOnlyDictionary<string, VsCodeMcpServer> Servers);

    private sealed record VsCodeMcpServer(
        [property: JsonPropertyName("type")] string Type,
        [property: JsonPropertyName("url")] string Url);
}
