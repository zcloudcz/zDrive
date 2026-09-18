using System.Net;
using System.Text;
using System.Text.Json;
using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using ModelContextProtocol;
using Xunit;
using ZDrive.ApiGateway.Mcp;

namespace ZDrive.ApiGateway.Tests.Mcp;

/// <summary>
/// Exercises the six MCP tools against a stubbed HttpMessageHandler instead
/// of real FileService/StorageService instances — these are unit tests of
/// tool logic (request shape, chunking, abort-on-failure, error mapping,
/// inline limit), not integration tests of the backend. See
/// McpProtocolTests for the one end-to-end test through the SDK's client.
/// </summary>
public sealed class ShareLinkToolsTests
{
    private const string Token = "test-token";
    private static readonly Guid FileId = Guid.NewGuid();
    private static readonly Guid ParentId = Guid.NewGuid();

    private sealed class FakeHttpClientFactory : IHttpClientFactory
    {
        private readonly HttpClient _fileService;
        private readonly HttpClient _storageService;

        public FakeHttpClientFactory(FakeHttpMessageHandler fileServiceHandler, FakeHttpMessageHandler storageServiceHandler)
        {
            _fileService = new HttpClient(fileServiceHandler) { BaseAddress = new Uri("http://file-service.test") };
            _storageService = new HttpClient(storageServiceHandler) { BaseAddress = new Uri("http://storage-service.test") };
        }

        public HttpClient CreateClient(string name) => name switch
        {
            "mcpFileService" => _fileService,
            "mcpStorageService" => _storageService,
            _ => throw new ArgumentOutOfRangeException(nameof(name), name, "Unexpected client name")
        };
    }

    private static ShareLinkTools BuildTools(
        FakeHttpMessageHandler fileServiceHandler, FakeHttpMessageHandler storageServiceHandler, long maxInlineBytes = 26_214_400)
    {
        var apiClient = new ShareLinkApiClient(new FakeHttpClientFactory(fileServiceHandler, storageServiceHandler));

        var httpContext = new DefaultHttpContext();
        httpContext.Items[ShareTokenAuth.TokenItemKey] = Token;
        var accessor = new HttpContextAccessor { HttpContext = httpContext };

        var options = Options.Create(new McpOptions { MaxInlineBytes = maxInlineBytes });

        return new ShareLinkTools(apiClient, accessor, options, NullLogger<ShareLinkTools>.Instance);
    }

    private static HttpResponseMessage Ok(object data) =>
        FakeHttpMessageHandler.Json(HttpStatusCode.OK, JsonSerializer.Serialize(new { success = true, data }));

    [Fact]
    public async Task ListFiles_WithFolderId_SendsFolderIdQueryToChildrenEndpoint()
    {
        var fileHandler = new FakeHttpMessageHandler(_ => Ok(new object[]
        {
            new { id = FileId, parentId = ParentId, name = "report.pdf", isFolder = false, sizeBytes = 42, updatedAt = "2026-09-18T10:00:00Z" }
        }));
        var storageHandler = new FakeHttpMessageHandler(_ => throw new InvalidOperationException("list_files must not call StorageService"));
        var tools = BuildTools(fileHandler, storageHandler);

        var result = await tools.list_files(ParentId, CancellationToken.None);

        fileHandler.Requests.Should().ContainSingle();
        var request = fileHandler.Requests[0];
        request.Method.Should().Be(HttpMethod.Get);
        request.RequestUri!.PathAndQuery.Should().Be($"/api/v1/shares/link/{Token}/children?folderId={ParentId}");

        using var doc = JsonDocument.Parse(result);
        var first = doc.RootElement[0];
        first.GetProperty("name").GetString().Should().Be("report.pdf");
        first.GetProperty("modifiedAt").GetDateTime().Should().Be(DateTime.Parse("2026-09-18T10:00:00Z").ToUniversalTime());
    }

    [Fact]
    public async Task ReadFile_ManifestOverInlineLimit_ThrowsWithoutDownloadingChunks()
    {
        var fileHandler = new FakeHttpMessageHandler(_ => Ok(new
        {
            grant = "download-grant", expiresAt = DateTimeOffset.UtcNow.AddHours(1),
            fileId = FileId, fileName = "big.bin", sizeBytes = 100, manifestHash = "hash"
        }));
        var storageHandler = new FakeHttpMessageHandler(request =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/bytes"))
                throw new InvalidOperationException("Must not download chunks once the size check has failed");

            return Ok(new { totalSize = 100_000_000, chunks = Array.Empty<object>() });
        });
        var tools = BuildTools(fileHandler, storageHandler, maxInlineBytes: 1000);

        var act = () => tools.read_file(FileId, "auto", CancellationToken.None);

        (await act.Should().ThrowAsync<McpException>()).WithMessage("*inline limit*");
    }

    [Fact]
    public async Task WriteFile_ContentOverFourMebibytes_SplitsIntoTwoChunksWithHashHeaders()
    {
        var content = new string('a', 5 * 1024 * 1024); // > one 4 MiB chunk
        var sessionId = Guid.NewGuid();

        var fileHandler = new FakeHttpMessageHandler(request => request.RequestUri!.AbsolutePath.EndsWith("/upload-grant")
            ? Ok(new { grant = "upload-grant", expiresAt = DateTimeOffset.UtcNow.AddHours(1), fileId = FileId, fileName = "big.txt", maxBytes = content.Length })
            : Ok(new { id = FileId, parentId = (Guid?)null, name = "big.txt", isFolder = false, sizeBytes = content.Length, updatedAt = DateTime.UtcNow }));

        var storageHandler = new FakeHttpMessageHandler(request =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/init"))
                return Ok(new { sessionId, sasUploadUrl = "unused" });
            if (request.RequestUri!.AbsolutePath.Contains("/chunk/"))
                return Ok(new { sessionId, chunkIndex = 0, chunkHash = "h", accepted = true });
            if (request.RequestUri!.AbsolutePath.EndsWith("/complete"))
                return Ok(new { manifestHash = "final-hash", totalSize = content.Length, receipt = "the-receipt" });

            throw new InvalidOperationException($"Unexpected storage request: {request.RequestUri}");
        });

        var tools = BuildTools(fileHandler, storageHandler);

        await tools.write_file("big.txt", content, "text", ParentId, false, CancellationToken.None);

        var chunkRequests = storageHandler.Requests.Where(r => r.RequestUri!.AbsolutePath.Contains("/chunk/")).ToList();
        chunkRequests.Should().HaveCount(2, "5 MiB of content at a 4 MiB chunk size needs two chunks");
        chunkRequests[0].RequestUri!.AbsolutePath.Should().EndWith("/chunk/0");
        chunkRequests[1].RequestUri!.AbsolutePath.Should().EndWith("/chunk/1");
        chunkRequests.Should().OnlyContain(r => r.Headers.Contains("X-Chunk-Hash") && r.Headers.Contains("X-Share-Grant"));
    }

    /// <summary>
    /// The "teeth" check: if the abort-on-failure call in ShareLinkTools.write_file
    /// were ever accidentally removed, this is the assertion that would fail —
    /// verified manually per the task's VERIFY step by commenting out the abort
    /// call, confirming this test goes red, then restoring it.
    /// </summary>
    [Fact]
    public async Task WriteFile_ChunkUploadFails_AbortsTheUploadSession()
    {
        var sessionId = Guid.NewGuid();
        var fileHandler = new FakeHttpMessageHandler(request => request.RequestUri!.AbsolutePath.EndsWith("/upload-grant")
            ? Ok(new { grant = "upload-grant", expiresAt = DateTimeOffset.UtcNow.AddHours(1), fileId = FileId, fileName = "f.txt", maxBytes = 5 })
            : throw new InvalidOperationException("must not reach files/{id}/versions when the upload itself failed"));

        var storageHandler = new FakeHttpMessageHandler(request =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/init"))
                return Ok(new { sessionId, sasUploadUrl = "unused" });
            if (request.Method == HttpMethod.Put && request.RequestUri!.AbsolutePath.Contains("/chunk/"))
                return new HttpResponseMessage(HttpStatusCode.InternalServerError);
            if (request.Method == HttpMethod.Delete)
                return new HttpResponseMessage(HttpStatusCode.OK);

            throw new InvalidOperationException($"Unexpected storage request: {request.RequestUri}");
        });

        var tools = BuildTools(fileHandler, storageHandler);

        var act = () => tools.write_file("f.txt", "hello", "text", null, false, CancellationToken.None);
        await act.Should().ThrowAsync<McpException>();

        storageHandler.Requests.Should().ContainSingle(
            r => r.Method == HttpMethod.Delete && r.RequestUri!.AbsolutePath.EndsWith($"/upload/{sessionId}"),
            "a failed chunk upload must abort the session instead of leaving it dangling");
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "does not allow")]
    [InlineData(HttpStatusCode.Conflict, "already exists")]
    public async Task CreateFolder_BackendError_MapsToPlainToolMessage(HttpStatusCode status, string expectedFragment)
    {
        var fileHandler = new FakeHttpMessageHandler(_ =>
            FakeHttpMessageHandler.Json(status, JsonSerializer.Serialize(new { success = false, error = new { code = "X", message = "backend detail" } })));
        var storageHandler = new FakeHttpMessageHandler(_ => throw new InvalidOperationException("create_folder must not call StorageService"));
        var tools = BuildTools(fileHandler, storageHandler);

        var act = () => tools.create_folder("dup", null, CancellationToken.None);

        (await act.Should().ThrowAsync<McpException>()).WithMessage($"*{expectedFragment}*");
    }

    [Fact]
    public async Task WriteFile_QuotaExceeded_PassesBackendMessageThrough()
    {
        var fileHandler = new FakeHttpMessageHandler(_ => FakeHttpMessageHandler.Json(
            HttpStatusCode.RequestEntityTooLarge,
            JsonSerializer.Serialize(new { success = false, error = new { code = "QUOTA_EXCEEDED", message = "Quota exceeded: 100 of 100 bytes used." } })));
        var storageHandler = new FakeHttpMessageHandler(_ => throw new InvalidOperationException("must not reach StorageService"));
        var tools = BuildTools(fileHandler, storageHandler);

        var act = () => tools.write_file("f.txt", "hello", "text", null, false, CancellationToken.None);

        (await act.Should().ThrowAsync<McpException>()).WithMessage("*100 of 100 bytes used*");
    }
}
