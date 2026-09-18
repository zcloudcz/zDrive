using System.Net;
using FluentAssertions;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Xunit;
using ZDrive.ApiGateway.Mcp;

namespace ZDrive.ApiGateway.Tests.Mcp;

/// <summary>
/// Unit tests for ShareTokenAuth.Filter itself — status-code mapping and the
/// per-endpoint request body size override — built directly against
/// EndpointFilterInvocationContext.Create rather than a full host, since
/// TestServer doesn't attach a real IHttpMaxRequestBodySizeFeature (that's a
/// Kestrel-specific feature) and can't reproduce a genuine transport 413.
/// </summary>
public sealed class ShareTokenAuthTests
{
    private sealed class FakeBodySizeFeature : IHttpMaxRequestBodySizeFeature
    {
        public bool IsReadOnly => false;
        public long? MaxRequestBodySize { get; set; } = 30_000_000; // Kestrel's real default
    }

    private static (HttpContext Context, FakeBodySizeFeature BodyFeature) BuildContext(ShareValidationResult validationResult, long maxInlineBytes = 26_214_400)
    {
        var services = new ServiceCollection();
        services.AddSingleton(Options.Create(new McpOptions { MaxInlineBytes = maxInlineBytes }));
        services.AddSingleton(new ShareLinkApiClient(new FixedResultHttpClientFactory(validationResult)));
        var provider = services.BuildServiceProvider();

        var bodyFeature = new FakeBodySizeFeature();
        var context = new DefaultHttpContext { RequestServices = provider };
        context.Features.Set<IHttpMaxRequestBodySizeFeature>(bodyFeature);

        return (context, bodyFeature);
    }

    /// <summary>Stands in for FileService: always answers the ShareLinkApiClient's
    /// GET shares/link/{token} with whatever status the test wants, without a real HTTP call.</summary>
    private sealed class FixedResultHttpClientFactory : IHttpClientFactory
    {
        private readonly HttpClient _client;

        public FixedResultHttpClientFactory(ShareValidationResult result)
        {
            var status = result switch
            {
                ShareValidationResult.Ok => HttpStatusCode.OK,
                ShareValidationResult.NotFound => HttpStatusCode.NotFound,
                ShareValidationResult.Forbidden => HttpStatusCode.Forbidden,
                ShareValidationResult.Unavailable => HttpStatusCode.InternalServerError,
                _ => throw new ArgumentOutOfRangeException(nameof(result))
            };
            var body = result == ShareValidationResult.Ok
                ? """{"success":true,"data":{}}"""
                : """{"success":false,"error":{"code":"X","message":"m"}}""";
            _client = new HttpClient(new FakeHttpMessageHandler(_ => FakeHttpMessageHandler.Json(status, body)))
            {
                BaseAddress = new Uri("http://file-service.test")
            };
        }

        public HttpClient CreateClient(string name) => _client;
    }

    [Fact]
    public async Task Filter_ValidToken_SetsMaxRequestBodySizeFromMcpOptions()
    {
        var (context, bodyFeature) = BuildContext(ShareValidationResult.Ok, maxInlineBytes: 26_214_400);
        context.Request.Headers.Authorization = "Bearer valid-token";
        var invocationContext = EndpointFilterInvocationContext.Create(context);

        await ShareTokenAuth.Filter(tokenFromHeader: true, notFoundStatus: 401)(invocationContext, _ => ValueTask.FromResult<object?>("ok"));

        // 26_214_400 * 4/3 + 1 MiB, per the fix: base64 expansion plus JSON-RPC envelope slack.
        bodyFeature.MaxRequestBodySize.Should().Be(26_214_400L * 4 / 3 + 1024 * 1024);
    }

    [Fact]
    public async Task Filter_BackendUnavailable_Returns503AndDoesNotCallNext()
    {
        var (context, _) = BuildContext(ShareValidationResult.Unavailable);
        context.Request.Headers.Authorization = "Bearer any-token";
        var invocationContext = EndpointFilterInvocationContext.Create(context);
        var nextCalled = false;

        await ShareTokenAuth.Filter(tokenFromHeader: true, notFoundStatus: 401)(
            invocationContext, _ => { nextCalled = true; return ValueTask.FromResult<object?>("ok"); });

        context.Response.StatusCode.Should().Be(StatusCodes.Status503ServiceUnavailable);
        nextCalled.Should().BeFalse();
    }

    [Fact]
    public async Task Filter_UnknownToken_Returns404NotSameAsBackendOutage()
    {
        var (context, _) = BuildContext(ShareValidationResult.NotFound);
        context.Request.RouteValues["token"] = "unknown";
        var invocationContext = EndpointFilterInvocationContext.Create(context);

        await ShareTokenAuth.Filter(tokenFromHeader: false, notFoundStatus: 404)(invocationContext, _ => ValueTask.FromResult<object?>("ok"));

        context.Response.StatusCode.Should().Be(StatusCodes.Status404NotFound);
    }
}
