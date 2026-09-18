using System.Net;
using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;

namespace ZDrive.ApiGateway.Tests.Mcp;

/// <summary>
/// Boots the real gateway (Development, for the dev JWT key pair — same as
/// GatewayFactory) but swaps the two named HttpClients the MCP tools use for
/// stubbed handlers, since FileService/StorageService aren't running in this
/// test process and Package A's write-API endpoints don't exist on this
/// branch yet (see the contract: Package A ships in parallel). This is a
/// protocol-level test of the gateway's own MCP wiring — token validation
/// through to a tool call — not an integration test of the backend.
/// </summary>
public sealed class McpTestFactory : WebApplicationFactory<Program>
{
    public const string ValidToken = "valid-share-token";
    public static readonly Guid RootFileId = Guid.NewGuid();
    public static readonly Guid ChildFileId = Guid.NewGuid();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");

        builder.ConfigureServices(services =>
        {
            services.AddHttpClient("mcpFileService").ConfigurePrimaryHttpMessageHandler(() => new FakeHttpMessageHandler(HandleFileServiceRequest));
            services.AddHttpClient("mcpStorageService").ConfigurePrimaryHttpMessageHandler(() =>
                new FakeHttpMessageHandler(_ => throw new InvalidOperationException("This test does not exercise StorageService calls")));
        });
    }

    private static HttpResponseMessage HandleFileServiceRequest(HttpRequestMessage request)
    {
        var path = request.RequestUri!.AbsolutePath;

        // ShareTokenAuth's cheap validation call — the existing (already-on-master) GET shares/link/{token}.
        if (path == $"/api/v1/shares/link/{ValidToken}")
            return Ok(new { share = new { permission = "Read" }, file = new { id = RootFileId, name = "root", isFolder = true } });

        if (path == $"/api/v1/shares/link/{ValidToken}/children")
        {
            return Ok(new object[]
            {
                new { id = ChildFileId, parentId = RootFileId, name = "notes.txt", isFolder = false, sizeBytes = 5, updatedAt = DateTime.UtcNow }
            });
        }

        return new HttpResponseMessage(HttpStatusCode.NotFound);
    }

    private static HttpResponseMessage Ok(object data) =>
        FakeHttpMessageHandler.Json(HttpStatusCode.OK, JsonSerializer.Serialize(new { success = true, data }));
}
