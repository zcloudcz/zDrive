using FluentAssertions;
using ModelContextProtocol.Client;
using Xunit;

namespace ZDrive.ApiGateway.Tests.Mcp;

/// <summary>
/// The share token travels IN THE REQUEST PATH to FileService/StorageService
/// (/api/v1/shares/link/{token}/...), and HttpClient's default logging
/// (System.Net.Http.HttpClient.*.LogicalHandler/ClientHandler, at
/// Information) logs the full request URI — a live credential in the console
/// and Seq sinks on every MCP request, unless the appsettings.json
/// Serilog:MinimumLevel:Override silences that category. This test captures
/// the real Console sink's output (the gateway's Serilog pipeline writes via
/// Console.Out, not a mockable abstraction) through an MCP call made via the
/// URL-token endpoint, so the token appears in both the outbound HttpClient
/// call AND the inbound request the gateway itself is handling.
/// </summary>
[Trait("Category", "Integration")]
public sealed class LoggingTests
{
    [Fact]
    public async Task McpCallThroughRouteTokenEndpoint_NeverLogsTheTokenToConsole()
    {
        var originalOut = Console.Out;
        var captured = new StringWriter();

        await using var factory = new McpTestFactory();
        var httpClient = factory.CreateClient();

        Console.SetOut(captured);
        try
        {
            var transport = new HttpClientTransport(
                new HttpClientTransportOptions { Endpoint = new Uri(httpClient.BaseAddress!, $"/mcp/s/{McpTestFactory.ValidToken}") },
                httpClient);

            await using var mcpClient = await McpClient.CreateAsync(transport);
            await mcpClient.CallToolAsync("list_files", new Dictionary<string, object?>());
        }
        finally
        {
            Console.SetOut(originalOut);
        }

        captured.ToString().Should().NotContain(
            McpTestFactory.ValidToken,
            "the share token must never reach a log sink — it is a bearer credential, not diagnostic data");
    }
}
