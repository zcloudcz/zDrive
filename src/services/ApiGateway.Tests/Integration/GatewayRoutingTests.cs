using System.Net;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using Yarp.ReverseProxy.Configuration;

namespace ZDrive.ApiGateway.Tests.Integration;

/// <summary>
/// The gateway's route table is the only thing standing between the Flutter
/// client and a service: a path with no route is a 404 no matter how healthy
/// the service behind it is. Albums, memories and notifications were all
/// implemented and unreachable for exactly that reason, so these tests assert
/// that each path is routed rather than swallowed.
/// </summary>
[Trait("Category", "Integration")]
public sealed class GatewayRoutingTests : IClassFixture<GatewayFactory>
{
    private readonly GatewayFactory _factory;

    public GatewayRoutingTests(GatewayFactory factory)
    {
        _factory = factory;
    }

    // A routed-but-protected path answers 401; an unrouted one answers 404.
    // That difference is what makes these assertions meaningful — see
    // UnmappedPath_WithoutToken_ReturnsNotFound for the control case.
    [Theory]
    [InlineData("/api/v1/albums")]
    [InlineData("/api/v1/albums/00000000-0000-0000-0000-000000000000/photos")]
    [InlineData("/api/v1/memories")]
    [InlineData("/api/v1/notifications")]
    [InlineData("/api/v1/photos/timeline")]
    [InlineData("/api/v1/files/trash")]
    public async Task ProtectedRoute_WithoutToken_ReturnsUnauthorized(string path)
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync(path);

        response.StatusCode.Should().Be(
            HttpStatusCode.Unauthorized,
            "{0} must reach the gateway's authorization policy, not fall through as an unrouted path",
            path);
    }

    [Fact]
    public async Task UnmappedPath_WithoutToken_ReturnsNotFound()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync("/api/v1/not-a-real-resource");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    /// <summary>
    /// The SignalR hub route deliberately carries no AuthorizationPolicy.
    /// SignalR passes its token in the <c>access_token</c> query string
    /// because the browser WebSocket transport cannot send an Authorization
    /// header, and NotificationService reads it there
    /// (<c>NotificationService.Infrastructure.DependencyInjection</c> installs
    /// an <c>OnMessageReceived</c> handler scoped to /hubs/sync). The gateway
    /// has no such handler, so applying its default policy would 401 a request
    /// the destination can authenticate perfectly well.
    /// </summary>
    /// <remarks>
    /// Asserted against the route table rather than by issuing a request: a
    /// developer running NotificationService locally on :5106 would get a real
    /// 401 from the hub's [Authorize] and turn a status-code assertion red.
    /// </remarks>
    [Fact]
    public void SyncHubRoute_IsRoutedWithoutAuthorizationPolicy()
    {
        var config = _factory.Services.GetRequiredService<IProxyConfigProvider>().GetConfig();

        var hubRoute = config.Routes.Should().ContainSingle(
            route => route.Match.Path == "/hubs/sync/{**catch-all}",
            "the SignalR hub must be routed").Subject;

        hubRoute.ClusterId.Should().Be("notificationCluster");
        hubRoute.AuthorizationPolicy.Should().BeNull(
            "the hub authenticates from the access_token query string, which the gateway does not read");
    }
}
