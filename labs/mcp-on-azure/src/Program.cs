using McpOnAzure;
using McpOnAzure.Tools;

var builder = WebApplication.CreateBuilder(args);

var storageAccount = builder.Configuration["AZURE_STORAGE_ACCOUNT_NAME"]
    ?? Environment.GetEnvironmentVariable("AZURE_STORAGE_ACCOUNT_NAME")
    ?? throw new InvalidOperationException("AZURE_STORAGE_ACCOUNT_NAME is required.");

var containerName = builder.Configuration["AZURE_STORAGE_CONTAINER_NAME"]
    ?? Environment.GetEnvironmentVariable("AZURE_STORAGE_CONTAINER_NAME")
    ?? "mcp-demo";

var platformOnlyContainer = builder.Configuration["AZURE_STORAGE_PLATFORM_ONLY_CONTAINER_NAME"]
    ?? Environment.GetEnvironmentVariable("AZURE_STORAGE_PLATFORM_ONLY_CONTAINER_NAME")
    ?? "mcp-platform-only";

builder.Services.AddSingleton(new StorageOptions(storageAccount, containerName, platformOnlyContainer));
builder.Services.AddSingleton<PlatformBlobService>();
builder.Services.AddHttpContextAccessor();
builder.Services.AddSingleton<UserBlobService>();
builder.Services.AddSingleton<ILabConfigService, LabConfigService>();
builder.Services.AddRazorPages();
builder.Services.AddMcpEntraAuth(builder.Configuration);

builder.Services
    .AddMcpServer(options =>
    {
        options.ServerInfo = new()
        {
            Name = "mcp-on-azure",
            Version = "0.1.7",
        };
    })
    .WithHttpTransport()
    .WithToolsFromAssembly();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

app.MapRazorPages();
app.MapGet("/health", () => Results.Ok(new { status = "ok", lab = "mcp-on-azure" }));
app.MapGet("/config.json", (ILabConfigService labConfig, HttpRequest request) =>
    Results.Json(labConfig.GetPublicConfig(request).ToJsonDto()));
app.MapMcpProtectedResourceMetadata();
app.MapMcp("/mcp").RequireAuthorization();

await app.RunAsync();
