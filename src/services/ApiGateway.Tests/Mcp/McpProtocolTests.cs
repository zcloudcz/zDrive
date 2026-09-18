using FluentAssertions;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;
using Xunit;

namespace ZDrive.ApiGateway.Tests.Mcp;

/// <summary>
/// One end-to-end test through the real MCP SDK client, per the contract's
/// Package C test list: initialize → list tools → call a tool, against the
/// gateway's actual /mcp endpoint (McpTestFactory only stubs the two
/// downstream HttpClients, not anything MCP-specific).
/// </summary>
[Trait("Category", "Integration")]
public sealed class McpProtocolTests
{
    [Fact]
    public async Task InitializeListToolsAndCallListFiles_ThroughBearerEndpoint_Succeeds()
    {
        await using var factory = new McpTestFactory();
        var httpClient = factory.CreateClient();

        var transport = new HttpClientTransport(
            new HttpClientTransportOptions
            {
                Endpoint = new Uri(httpClient.BaseAddress!, "/mcp"),
                AdditionalHeaders = new Dictionary<string, string> { ["Authorization"] = $"Bearer {McpTestFactory.ValidToken}" }
            },
            httpClient);

        await using var mcpClient = await McpClient.CreateAsync(transport);

        var tools = await mcpClient.ListToolsAsync();
        tools.Select(t => t.Name).Should().BeEquivalentTo(
            "get_info", "list_files", "read_file", "write_file", "create_folder", "delete_item");

        var result = await mcpClient.CallToolAsync("list_files", new Dictionary<string, object?>());

        var text = result.Content.OfType<TextContentBlock>().Single().Text;
        result.IsError.Should().NotBe(true, "tool call failed: {0}", text);
        text.Should().Contain("notes.txt");
    }
}
