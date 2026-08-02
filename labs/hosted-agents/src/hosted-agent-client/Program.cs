using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Azure.Core;
using Azure.Identity;
using DotNetEnv;

class Program
{
    static HttpClient http = new HttpClient();
    static DefaultAzureCredential cred = new DefaultAzureCredential();
    static string? token = null;
    static DateTimeOffset expires = DateTimeOffset.MinValue;
    static bool firstMessage = true;

    static async Task<string> GetToken()
    {
        if (token != null && DateTimeOffset.UtcNow < expires.AddSeconds(-60))
            return token;
        var t = await cred.GetTokenAsync(
            new TokenRequestContext(
                new[] { "https://ai.azure.com/.default" }));
        token = t.Token;
        expires = t.ExpiresOn;
        return token;
    }

    static async Task<JsonDocument> CallAgent(string endpoint, string msg)
    {
        var t = await GetToken();
        var req = new { input = msg, store = true, stream = false };
        var content = new StringContent(
            JsonSerializer.Serialize(req),
            Encoding.UTF8,
            "application/json");
        var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = content
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", t);
        var resp = await http.SendAsync(request);
        resp.EnsureSuccessStatusCode();
        return JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
    }

    static string ExtractResponseText(JsonDocument d)
    {
        var r = d.RootElement;
        if (r.TryGetProperty("output", out var o))
            return o.GetString() ?? "";
        if (r.TryGetProperty("choices", out var c) && c.GetArrayLength() > 0)
        {
            var m = c[0].GetProperty("message").GetProperty("content");
            return m.GetString() ?? "";
        }
        if (r.TryGetProperty("value", out var v) &&
            v.TryGetProperty("outputText", out var ot))
            return ot.GetString() ?? "";
        return JsonSerializer.Serialize(r, new JsonSerializerOptions { WriteIndented = true });
    }

    static JsonDocument? LoadAppSettings()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "appsettings.json");
        if (!File.Exists(path))
        {
            path = "appsettings.json";
            if (!File.Exists(path))
                return null;
        }
        try
        {
            var json = File.ReadAllText(path);
            return JsonDocument.Parse(json);
        }
        catch
        {
            return null;
        }
    }

    static (string? endpoint, string? agentName) GetSettingsFromAppSettings()
    {
        var settings = LoadAppSettings();
        if (settings == null) return (null, null);

        if (settings.RootElement.TryGetProperty("FoundrySettings", out var foundry) &&
            foundry.ValueKind == JsonValueKind.Object)
        {
            var endpoint = foundry.TryGetProperty("Endpoint", out var ep) ? ep.GetString() : null;
            var agentName = foundry.TryGetProperty("AgentName", out var an) ? an.GetString() : null;
            return (endpoint, agentName);
        }

        return (null, null);
    }

    static void PrintHeader()
    {
        Console.WriteLine();
        Console.WriteLine("  =============================================================");
        Console.WriteLine("        Azure AI Foundry - Hosted Agent CLI Client");
        Console.WriteLine("  =============================================================");
        Console.WriteLine();
    }

    static void PrintUsage()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine("  dotnet run [endpoint] [agent]");
        Console.WriteLine();
        Console.WriteLine("Configuration (in order of precedence):");
        Console.WriteLine("  1. Command line arguments");
        Console.WriteLine("  2. Environment variables (FOUNDRY_ENDPOINT, AGENT_NAME)");
        Console.WriteLine("  3. appsettings.json file");
        Console.WriteLine("  4. Defaults (AgentName: hello-world-dotnet-responses)");
        Console.WriteLine();
        Console.WriteLine("Examples:");
        Console.WriteLine("  dotnet run                                   # Uses appsettings.json");
        Console.WriteLine("  dotnet run https://.../projects/my-project   # Override endpoint");
        Console.WriteLine("  FOUNDRY_ENDPOINT=https://... dotnet run   # Environment variable");
        Console.WriteLine();
        Console.WriteLine("Authentication:");
        Console.WriteLine("  Run 'az login' first, or set AZURE_CLIENT_ID/SECRET/TENANT_ID");
        Console.WriteLine();
    }

    static void PrintWelcome(string endpoint, string agent)
    {
        Console.WriteLine("Connected to:");
        Console.WriteLine("  Endpoint: " + endpoint);
        Console.WriteLine("  Agent:    " + agent);
        Console.WriteLine();
        Console.WriteLine("Type your messages below. Type 'exit', 'quit', 'q', or 'bye' to end.");
        Console.WriteLine("Type 'help' or '?' for available commands.");
        Console.WriteLine();
    }

    static void PrintGoodbye()
    {
        Console.WriteLine();
        Console.WriteLine("Goodbye!");
        Console.WriteLine();
    }

    static async Task Main(string[] args)
    {
        try
        {
            Env.TraversePath().NoClobber().Load();

            PrintHeader();

            var (appSettingsEndpoint, appSettingsAgent) = GetSettingsFromAppSettings();

            var endpoint = args.Length > 0
                ? args[0]
                : Environment.GetEnvironmentVariable("FOUNDRY_ENDPOINT") ??
                  appSettingsEndpoint;
            var agent = args.Length > 1
                ? args[1]
                : Environment.GetEnvironmentVariable("AGENT_NAME") ??
                  appSettingsAgent ??
                  "hello-world-dotnet-responses";

            if (string.IsNullOrEmpty(endpoint))
            {
                Console.WriteLine("Error: Foundry endpoint is required.");
                Console.WriteLine();
                PrintUsage();
                return;
            }

            endpoint = endpoint.TrimEnd('/') +
                "/agents/" + agent +
                "/endpoint/protocols/openai/responses?api-version=v1";

            PrintWelcome(endpoint, agent);

            while (true)
            {
                try
                {
                    if (firstMessage)
                    {
                        Console.Write("You: ");
                        firstMessage = false;
                    }
                    else
                    {
                        Console.Write("\nYou: ");
                    }

                    var input = Console.ReadLine()?.Trim();

                    if (string.IsNullOrEmpty(input))
                    {
                        continue;
                    }

                    if (input.Equals("exit", StringComparison.OrdinalIgnoreCase) ||
                        input.Equals("quit", StringComparison.OrdinalIgnoreCase) ||
                        input.Equals("q", StringComparison.OrdinalIgnoreCase) ||
                        input.Equals("bye", StringComparison.OrdinalIgnoreCase))
                    {
                        PrintGoodbye();
                        break;
                    }

                    if (input.Equals("help", StringComparison.OrdinalIgnoreCase) ||
                        input.Equals("?", StringComparison.OrdinalIgnoreCase))
                    {
                        Console.WriteLine("\nCommands:");
                        Console.WriteLine("  exit, quit, q, bye  - Exit the chat");
                        Console.WriteLine("  help, ?          - Show this help");
                        Console.WriteLine("  clear            - Clear the screen");
                        continue;
                    }

                    if (input.Equals("clear", StringComparison.OrdinalIgnoreCase))
                    {
                        Console.Clear();
                        PrintHeader();
                        Console.WriteLine("Connected to:");
                        Console.WriteLine("  Endpoint: " + endpoint);
                        Console.WriteLine("  Agent:    " + agent);
                        Console.WriteLine();
                        continue;
                    }

                    Console.Write("Agent: ");

                    var sw = Stopwatch.StartNew();
                    var resp = await CallAgent(endpoint, input);
                    sw.Stop();

                    var responseText = ExtractResponseText(resp);
                    Console.Write(responseText);

                    Console.WriteLine();
                    Console.ForegroundColor = ConsoleColor.DarkGray;
                    Console.WriteLine("  Response time: " + sw.Elapsed.TotalSeconds.ToString("F2") + "s");
                    Console.ResetColor();
                }
                catch (HttpRequestException httpEx)
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("\nError: " + httpEx.Message);
                    if (httpEx.StatusCode.HasValue)
                    {
                        Console.WriteLine("  Status: " + (int)httpEx.StatusCode.Value + " " + httpEx.StatusCode.Value);
                    }
                    Console.ResetColor();
                    Console.WriteLine("\nPlease check:");
                    Console.WriteLine("  - Your Azure authentication (run 'az login')");
                    Console.WriteLine("  - The endpoint URL is correct");
                    Console.WriteLine("  - The agent is deployed and running");
                    Console.WriteLine("\nType 'exit' to quit, or continue chatting.");
                }
                catch (Exception ex)
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("\nError: " + ex.Message);
                    Console.ResetColor();
                    Console.WriteLine("\nType 'exit' to quit, or continue chatting.");
                }
            }
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine("\nUnexpected error: " + ex.Message);
            Console.ResetColor();
        }
    }
}
