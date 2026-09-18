using System.Net;
using System.Text.Json;
using FluentAssertions;
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
}
