namespace McpOnAzure;

/// <summary>Public meetup config shown on the landing page and /config.json.</summary>
public sealed record LabPublicConfig(
    string Lab,
    string PublicBaseUrl,
    string McpUrl,
    string Resource,
    string TenantId,
    string ClientId,
    string Scope,
    string AuthorizationServer,
    string PrmUrl,
    IReadOnlyList<string> Tools,
    string TokenCommand,
    string VsCodeMcpJson)
{
    public object ToJsonDto() => new
    {
        lab = Lab,
        mcpUrl = McpUrl,
        resource = Resource,
        prmUrl = PrmUrl,
        authorizationServer = AuthorizationServer,
        entra = new { tenantId = TenantId, clientId = ClientId, scope = Scope },
        tools = Tools,
        tokenCommand = TokenCommand,
        vscodeMcpJson = VsCodeMcpJson,
    };

    public ProtectedResourceMetadata ToProtectedResourceMetadata() => new(
        Resource: Resource,
        AuthorizationServers: [AuthorizationServer],
        ScopesSupported: [Scope],
        BearerMethodsSupported: ["header"]);
}
