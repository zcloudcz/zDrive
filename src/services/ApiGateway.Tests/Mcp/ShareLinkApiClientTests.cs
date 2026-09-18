using System.Net;
using System.Text.Json;
using FluentAssertions;
using ModelContextProtocol;
using Xunit;
using ZDrive.ApiGateway.Mcp;

namespace ZDrive.ApiGateway.Tests.Mcp;

/// <summary>
/// ValidateTokenAsync's own mapping — the endpoint filter (ShareTokenAuth)
/// just forwards whatever this returns to a status code, so the "backend
/// outage vs bad token" distinction has to be right here.
/// </summary>
public sealed class ShareLinkApiClientTests
{
    private sealed class SingleClientFactory : IHttpClientFactory
    {
        private readonly HttpClient _client;
        public SingleClientFactory(FakeHttpMessageHandler handler) =>
            _client = new HttpClient(handler) { BaseAddress = new Uri("http://file-service.test") };

        public HttpClient CreateClient(string name) => _client;
    }

    [Fact]
    public async Task ValidateTokenAsync_BackendReturns500_ReportsUnavailableNotNotFound()
    {
        var handler = new FakeHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.InternalServerError));
        var client = new ShareLinkApiClient(new SingleClientFactory(handler));

        var result = await client.ValidateTokenAsync("tok", CancellationToken.None);

        result.Should().Be(ShareValidationResult.Unavailable);
    }

    [Fact]
    public async Task ValidateTokenAsync_ConnectionFails_ReportsUnavailable()
    {
        var handler = new FakeHttpMessageHandler(_ => throw new HttpRequestException("connection refused"));
        var client = new ShareLinkApiClient(new SingleClientFactory(handler));

        var result = await client.ValidateTokenAsync("tok", CancellationToken.None);

        result.Should().Be(ShareValidationResult.Unavailable);
    }

    [Fact]
    public async Task ValidateTokenAsync_TokenUnknown_ReportsNotFoundNotUnavailable()
    {
        var handler = new FakeHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.NotFound));
        var client = new ShareLinkApiClient(new SingleClientFactory(handler));

        var result = await client.ValidateTokenAsync("tok", CancellationToken.None);

        result.Should().Be(ShareValidationResult.NotFound);
    }

    /// <summary>
    /// Package A's own 429 (upload-grant's pending-uploads cap) carries
    /// TOO_MANY_PENDING_UPLOADS in the envelope — only that case gets the
    /// specific wording.
    /// </summary>
    [Fact]
    public async Task GetInfoAsync_429WithPendingUploadsCode_UsesPendingUploadsMessage()
    {
        var handler = new FakeHttpMessageHandler(_ => FakeHttpMessageHandler.Json(
            HttpStatusCode.TooManyRequests,
            JsonSerializer.Serialize(new { success = false, error = new { code = "TOO_MANY_PENDING_UPLOADS", message = "..." } })));
        var client = new ShareLinkApiClient(new SingleClientFactory(handler));

        var act = () => client.GetInfoAsync("tok", CancellationToken.None);

        (await act.Should().ThrowAsync<McpException>()).WithMessage("*limit of pending uploads*");
    }

    /// <summary>
    /// A gateway/ingress rate limiter can also answer 429 on any call, with no
    /// ApiResponse envelope at all — that must NOT be reported as the
    /// pending-uploads cap, which would be misleading.
    /// </summary>
    [Fact]
    public async Task GetInfoAsync_429WithNoEnvelope_UsesGenericTooManyRequestsMessage()
    {
        var handler = new FakeHttpMessageHandler(_ => new HttpResponseMessage(HttpStatusCode.TooManyRequests));
        var client = new ShareLinkApiClient(new SingleClientFactory(handler));

        var act = () => client.GetInfoAsync("tok", CancellationToken.None);

        var thrown = await act.Should().ThrowAsync<McpException>();
        thrown.WithMessage("*wait a moment and retry*");
        thrown.Which.Message.Should().NotContain("pending uploads");
    }
}
