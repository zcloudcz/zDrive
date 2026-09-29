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

    [Theory]
    [InlineData("photos-route")]
    [InlineData("albums-route")]
    [InlineData("memories-route")]
    public void PhotoRoutes_PointAtTheMergedApiCluster(string routeId)
    {
        var config = _factory.Services.GetRequiredService<IProxyConfigProvider>().GetConfig();

        config.Routes.Should().ContainSingle(r => r.RouteId == routeId).Which
            .ClusterId.Should().Be("apiCluster");
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
    public void ThumbnailRoute_HasItsOwnRateLimitPolicy_AndOnlyMatchesThumbnailPaths()
    {
        var config = _factory.Services.GetRequiredService<IProxyConfigProvider>().GetConfig();

        var route = config.Routes.Should().ContainSingle(r => r.RouteId == "photos-thumbnail-route").Subject;

        route.Match.Path.Should().Be("/api/v1/photos/{id}/thumbnail/{size}");
        route.ClusterId.Should().Be("apiCluster");
        route.RateLimiterPolicy.Should().Be("thumbnail");
        route.AuthorizationPolicy.Should().Be("default");

        // Every other photo route keeps the shared budget.
        config.Routes.Where(r => r.RouteId is "photos-route" or "albums-route" or "memories-route")
            .Should().OnlyContain(r => r.RateLimiterPolicy == "fixed");
    }

    [Fact]
    public async Task ThumbnailPath_WithoutToken_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync($"/api/v1/photos/{Guid.NewGuid()}/thumbnail/256");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

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

    /// <summary>
    /// Public share-link endpoints (anonymous manifest/chunk downloads by
    /// visitors with no JWT) must not carry the gateway's default
    /// AuthorizationPolicy, and must use their own "publicShare" rate-limit
    /// budget rather than sharing "fixed" or "auth" with unrelated traffic.
    /// </summary>
    [Theory]
    [InlineData("sharesLinkRoute", "/api/v1/shares/link/{**catch-all}", "apiCluster")]
    [InlineData("storageSharedRoute", "/api/v1/storage/shared/{**catch-all}", "apiCluster")]
    public void PublicShareRoute_IsAnonymousWithPublicShareRateLimit(string routeId, string path, string clusterId)
    {
        var config = _factory.Services.GetRequiredService<IProxyConfigProvider>().GetConfig();

        var route = config.Routes.Should().ContainSingle(
            r => r.RouteId == routeId, "the public share route must be present").Subject;

        route.Match.Path.Should().Be(path);
        route.ClusterId.Should().Be(clusterId);
        route.AuthorizationPolicy.Should().BeNull("a share-link visitor carries no JWT");
        route.RateLimiterPolicy.Should().Be("publicShare");
    }

    /// <summary>
    /// YARP orders routes by template specificity, so the more specific
    /// "link"/"shared" routes above must win over the catch-all authenticated
    /// routes for the same prefix — otherwise every anonymous share request
    /// would 401 against the "shares-route"/"storage-route" AuthorizationPolicy,
    /// which is the exact bug this feature fixes.
    /// </summary>
    [Theory]
    [InlineData("/api/v1/shares/link/abc123")]
    public async Task ShareLinkPath_WithoutToken_DoesNotReturnUnauthorized(string path)
    {
        var client = _factory.CreateClient();

        var response = await client.GetAsync(path);

        // FileService isn't actually running behind this test gateway, so the
        // proxy attempt itself fails — the point is that it gets far enough to
        // try, instead of being rejected by the gateway's own authorization.
        response.StatusCode.Should().NotBe(HttpStatusCode.Unauthorized);
    }

    /// <summary>
    /// A route naming a cluster that does not exist is not a startup error in
    /// YARP — the request simply fails at proxy time, and the status-code tests
    /// above still pass because an unmatched cluster never reaches them. Every
    /// ClusterId therefore has to be checked against the cluster table.
    /// </summary>
    [Fact]
    public void EveryRoute_PointsAtADefinedCluster()
    {
        var config = _factory.Services.GetRequiredService<IProxyConfigProvider>().GetConfig();
        var clusterIds = config.Clusters.Select(cluster => cluster.ClusterId).ToHashSet();

        foreach (var route in config.Routes)
        {
            clusterIds.Should().Contain(
                route.ClusterId,
                "route {0} names cluster {1}, which is not defined",
                route.RouteId,
                route.ClusterId);
        }
    }

    /// <summary>
    /// Cluster and destination ids are spliced into environment variable names
    /// (<c>ReverseProxy__Clusters__{cluster}__Destinations__{destination}__Address</c>)
    /// to point a deployment at its real service URLs. Azure App Service on
    /// Linux rejects any app setting name containing a hyphen with a bare
    /// "Bad Request", so a hyphen here silently costs us the ability to
    /// configure the gateway at all — it would keep proxying to localhost.
    /// </summary>
    [Fact]
    public void ClusterAndDestinationIds_ContainNoHyphens()
    {
        var config = _factory.Services.GetRequiredService<IProxyConfigProvider>().GetConfig();

        foreach (var cluster in config.Clusters)
        {
            cluster.ClusterId.Should().NotContain(
                "-", "cluster ids become environment variable names, which cannot contain hyphens");

            foreach (var destinationId in cluster.Destinations?.Keys ?? Enumerable.Empty<string>())
            {
                destinationId.Should().NotContain(
                    "-",
                    "destination id {0} in cluster {1} becomes part of an environment variable name",
                    destinationId,
                    cluster.ClusterId);
            }
        }
    }
}
