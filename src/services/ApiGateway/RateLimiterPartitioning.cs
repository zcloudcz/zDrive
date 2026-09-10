using System.Security.Claims;
using ZDrive.Shared.Auth;

namespace ZDrive.ApiGateway;

/// <summary>
/// Picks the rate-limit partition key for a request: the authenticated
/// user's id when present, otherwise the caller's IP address.
///
/// The IP fallback exists for the "auth" policy (login/register), which is
/// unauthenticated by design and so has no user id to key on — those
/// requests are partitioned per client IP instead of sharing one global
/// budget. It also covers any other request that reaches the limiter
/// without a valid token.
/// </summary>
public static class RateLimiterPartitioning
{
    public static string GetPartitionKey(ClaimsPrincipal user, string? remoteIpAddress) =>
        user.FindFirst(JwtConstants.UserIdClaim)?.Value
            ?? remoteIpAddress
            ?? "unknown";
}
