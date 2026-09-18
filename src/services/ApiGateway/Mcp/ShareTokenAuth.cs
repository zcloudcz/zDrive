using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Primitives;

namespace ZDrive.ApiGateway.Mcp;

/// <summary>
/// Validates the share token for every /mcp and /mcp/s/{token} request before
/// it reaches the MCP endpoint, per the contract's "Package C" section: the
/// share token IS the credential here (there is no JWT), so this is the
/// gateway's only gate for these two routes. Wired as endpoint-group
/// middleware in GatewayMcp.MapShareLinkMcp rather than an ASP.NET
/// [Authorize] policy, because the 401-vs-404 status differs per route and
/// because the check is a live HTTP call to FileService, not a local claim.
/// </summary>
public static class ShareTokenAuth
{
    public const string TokenItemKey = "ShareToken";

    /// <param name="notFoundStatus">401 for /mcp (missing/unknown Authorization bearer), 404 for /mcp/s/{token} (the contract's rule for anonymous share-link paths: never confirm existence of a bad token).</param>
    /// <remarks>
    /// An endpoint filter rather than classic middleware: RouteGroupBuilder
    /// (what app.MapGroup returns) has no IApplicationBuilder.Use — filters
    /// are the group-scoped hook, and they cascade to MapMcp's nested groups
    /// the same way conventions do.
    /// </remarks>
    public static Func<EndpointFilterInvocationContext, EndpointFilterDelegate, ValueTask<object?>> Filter(bool tokenFromHeader, int notFoundStatus) =>
        async (filterContext, next) =>
        {
            var context = filterContext.HttpContext;
            var token = tokenFromHeader
                ? ExtractBearerToken(context.Request.Headers.Authorization)
                : context.Request.RouteValues["token"] as string;

            if (string.IsNullOrEmpty(token))
            {
                context.Response.StatusCode = notFoundStatus;
                return Results.Empty;
            }

            var apiClient = context.RequestServices.GetRequiredService<ShareLinkApiClient>();
            var result = await apiClient.ValidateTokenAsync(token, context.RequestAborted);

            switch (result)
            {
                case ShareValidationResult.NotFound:
                    context.Response.StatusCode = notFoundStatus;
                    return Results.Empty;
                case ShareValidationResult.Forbidden:
                    context.Response.StatusCode = StatusCodes.Status403Forbidden;
                    return Results.Empty;
            }

            context.Items[TokenItemKey] = token;
            return await next(filterContext);
        };

    private static string? ExtractBearerToken(StringValues authorizationHeader)
    {
        var value = authorizationHeader.ToString();
        const string prefix = "Bearer ";
        return value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) ? value[prefix.Length..].Trim() : null;
    }
}
