using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;

namespace McpOnAzure;

public static class McpAuthExtensions
{
    public const string JwtScheme = JwtBearerDefaults.AuthenticationScheme;

    public static IServiceCollection AddMcpEntraAuth(this IServiceCollection services, IConfiguration configuration)
    {
        var tenantId = Required(configuration, "MCP_ENTRA_TENANT_ID");
        var clientId = Required(configuration, "MCP_ENTRA_CLIENT_ID");
        var authority = $"https://login.microsoftonline.com/{tenantId}/v2.0";

        services
            .AddAuthentication(JwtScheme)
            .AddJwtBearer(JwtScheme, options =>
            {
                options.Authority = authority;
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    // v2 tokens use the app's client id as aud; also accept registered Application ID URIs.
                    ValidAudiences =
                    [
                        clientId,
                        Required(configuration, "MCP_ENTRA_RESOURCE", fallback: clientId),
                        FirstNonEmpty(
                            configuration["MCP_ENTRA_API_URI"],
                            Environment.GetEnvironmentVariable("MCP_ENTRA_API_URI")) ?? $"api://{clientId}",
                    ],
                    NameClaimType = "name",
                    RoleClaimType = "roles",
                };

                options.Events = new JwtBearerEvents
                {
                    OnChallenge = async context =>
                    {
                        // Replace the default challenge so MCP clients get RFC 9728 discovery.
                        context.HandleResponse();

                        var http = context.HttpContext;
                        var lab = http.RequestServices.GetRequiredService<ILabConfigService>();
                        var config = lab.GetPublicConfig(http.Request);
                        var prmUrl = $"{config.PublicBaseUrl.TrimEnd('/')}/.well-known/oauth-protected-resource";

                        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                        context.Response.Headers.WWWAuthenticate =
                            $"Bearer realm=\"mcp-on-azure\", resource_metadata=\"{prmUrl}\", scope=\"{config.Scope}\"";

                        await context.Response.WriteAsJsonAsync(new
                        {
                            error = "unauthorized",
                            error_description = "Bearer token required. Discover auth via Protected Resource Metadata.",
                            resource_metadata = prmUrl,
                        });
                    },
                };
            });

        services.AddAuthorization();
        return services;
    }

    public static IEndpointRouteBuilder MapMcpProtectedResourceMetadata(this IEndpointRouteBuilder endpoints)
    {
        // RFC 9728 — root and path-append forms clients may probe.
        endpoints.MapGet("/.well-known/oauth-protected-resource", (ILabConfigService lab, HttpRequest request) =>
            Results.Json(lab.GetPublicConfig(request).ToProtectedResourceMetadata()));

        endpoints.MapGet("/.well-known/oauth-protected-resource/mcp", (ILabConfigService lab, HttpRequest request) =>
            Results.Json(lab.GetPublicConfig(request).ToProtectedResourceMetadata()));

        return endpoints;
    }

    private static string Required(IConfiguration configuration, string key, string? fallback = null)
    {
        var value = configuration[key] ?? Environment.GetEnvironmentVariable(key) ?? fallback;
        if (string.IsNullOrWhiteSpace(value))
            throw new InvalidOperationException($"{key} is required for MCP Entra auth.");
        return value.Trim();
    }

    private static string? FirstNonEmpty(params string?[] values)
    {
        foreach (var value in values)
        {
            if (!string.IsNullOrWhiteSpace(value))
                return value.Trim();
        }

        return null;
    }
}

public sealed record ProtectedResourceMetadata(
    [property: JsonPropertyName("resource")] string Resource,
    [property: JsonPropertyName("authorization_servers")] IReadOnlyList<string> AuthorizationServers,
    [property: JsonPropertyName("scopes_supported")] IReadOnlyList<string> ScopesSupported,
    [property: JsonPropertyName("bearer_methods_supported")] IReadOnlyList<string> BearerMethodsSupported);
