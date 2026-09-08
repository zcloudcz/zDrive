using System.Net;
using FluentAssertions;
using Xunit;

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
    /// The SignalR hub route deliberately carries no AuthorizationPolicy: the
    /// browser WebSocket transport cannot send an Authorization header, so
    /// gating it at the gateway would reject the very transport the hub exists
    /// for. SyncHub is marked [Authorize], so NotificationService still
    /// enforces authentication once the request arrives.
    /// </summary>
    [Fact]
    public async Task SyncHubRoute_WithoutToken_IsForwardedInsteadOfRejected()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync("/hubs/sync");

        response.StatusCode.Should().NotBe(
            HttpStatusCode.Unauthorized,
            "the gateway must not reject the hub handshake — the WebSocket transport cannot carry an Authorization header");
        response.StatusCode.Should().NotBe(
            HttpStatusCode.NotFound,
            "the hub path must be routed to NotificationService");
    }
}
