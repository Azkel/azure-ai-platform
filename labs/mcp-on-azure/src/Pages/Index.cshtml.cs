using McpOnAzure;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace McpOnAzure.Pages;

public sealed class IndexModel(ILabConfigService labConfig) : PageModel
{
    public LabPublicConfig Config { get; private set; } = null!;

    public void OnGet() => Config = labConfig.GetPublicConfig(Request);
}
