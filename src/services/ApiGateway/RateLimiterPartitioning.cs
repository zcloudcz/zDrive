using System.Globalization;
using System.Security.Claims;
using System.Threading.RateLimiting;
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
///
/// Behind a reverse-proxy ingress (e.g. Azure Container Apps) this fallback
/// is not effective yet: <c>HttpContext.Connection.RemoteIpAddress</c> is
/// the ingress's own address for every caller, since nothing here calls
/// <c>UseForwardedHeaders</c> to recover the real client IP from
/// <c>X-Forwarded-For</c>. Until that is wired up, the "auth" policy is a
/// single shared budget for every unauthenticated caller in that
/// environment, not a per-client one.
/// </summary>
public static class RateLimiterPartitioning
{
    public static string GetPartitionKey(ClaimsPrincipal user, string? remoteIpAddress) =>
        user.FindFirst(JwtConstants.UserIdClaim)?.Value
            ?? remoteIpAddress
            ?? "unknown";

    /// <summary>
    /// The Retry-After header value (whole seconds, rounded up so a caller
    /// never retries a fraction of a second early) for a rejected lease, or
    /// null if the limiter didn't attach a RetryAfter estimate. Program.cs's
    /// OnRejected puts this on the 429 response; dio_client.dart's
    /// RetryInterceptor reads it to know exactly how long the fixed window
    /// has left, instead of guessing a backoff against a window length it
    /// cannot see.
    /// </summary>
    public static string? GetRetryAfterSeconds(RateLimitLease lease) =>
        lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter)
            ? ((int)Math.Ceiling(retryAfter.TotalSeconds)).ToString(CultureInfo.InvariantCulture)
            : null;
}
