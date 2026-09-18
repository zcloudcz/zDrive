namespace ZDrive.ApiGateway.Mcp;

/// <summary>
/// Wires the two MCP endpoints (see the contract's "Package C" section):
/// /mcp (token via Authorization: Bearer, for clients that can set headers)
/// and /mcp/s/{token} (token via the URL, for clients that can only be given
/// a link). Both get the "publicShare" rate limiter — the same budget the
/// anonymous share-link REST routes use, since an MCP session drives the same
/// backend calls a REST client would.
/// </summary>
public static class GatewayMcp
{
    public static void MapShareLinkMcp(WebApplication app)
    {
        var headerAuthGroup = app.MapGroup("/mcp");
        headerAuthGroup.AddEndpointFilter(ShareTokenAuth.Filter(tokenFromHeader: true, notFoundStatus: StatusCodes.Status401Unauthorized));
        headerAuthGroup.MapMcp().RequireRateLimiting("publicShare");

        var routeTokenGroup = app.MapGroup("/mcp/s/{token}");
        routeTokenGroup.AddEndpointFilter(ShareTokenAuth.Filter(tokenFromHeader: false, notFoundStatus: StatusCodes.Status404NotFound));
        routeTokenGroup.MapMcp().RequireRateLimiting("publicShare");
    }

    /// <summary>
    /// Reads the first configured destination for a YARP cluster
    /// (ReverseProxy:Clusters:{clusterId}:Destinations:*:Address) — the same
    /// address YARP itself proxies to, so the MCP tools stay in sync with
    /// whatever a deployment overrides via
    /// ReverseProxy__Clusters__{clusterId}__Destinations__{id}__Address.
    /// </summary>
    public static string GetFirstClusterAddress(IConfiguration configuration, string clusterId)
    {
        var destinationsSection = configuration.GetSection($"ReverseProxy:Clusters:{clusterId}:Destinations");
        var firstDestination = destinationsSection.GetChildren().FirstOrDefault()
            ?? throw new InvalidOperationException($"No destinations configured for cluster '{clusterId}'.");

        return firstDestination["Address"]
            ?? throw new InvalidOperationException($"Destination for cluster '{clusterId}' has no Address.");
    }
}
