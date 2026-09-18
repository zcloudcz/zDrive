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
    /// Partition key for the "publicShare" policy only — anonymous share
    /// visitors never carry a JWT, so GetPartitionKey's fallback path is all
    /// of them, and in the deployed setup (Azure App Service, see class
    /// remarks) RemoteIpAddress is the front end's own address for every
    /// caller. That collapses every visitor into ONE bucket, so a single 1
    /// GB shared download (~250 chunk requests) would 429 every other
    /// visitor sharing the App Service.
    ///
    /// X-Forwarded-For fixes that, but only its RIGHTMOST entry is
    /// trustworthy: Azure's front end appends the real client IP as the
    /// last hop, while a client is free to set X-Forwarded-For to anything
    /// itself — it only controls the entries to the LEFT of what the front
    /// end appends. Reading the leftmost entry would let a client hand
    /// every request a fresh, attacker-chosen partition key, defeating the
    /// limiter entirely (this is why the "auth" policy, which faces the
    /// same forwarded-header gap per the class remarks above, is NOT
    /// changed here — it isn't chunk-shaped traffic and widening its
    /// trust model isn't this change's job).
    /// </summary>
    public static string GetPublicSharePartitionKey(string? forwardedFor, string? remoteIpAddress) =>
        GetRightmostForwardedForEntry(forwardedFor) ?? remoteIpAddress ?? "unknown";

    private static string? GetRightmostForwardedForEntry(string? forwardedFor)
    {
        if (string.IsNullOrWhiteSpace(forwardedFor))
            return null;

        var entries = forwardedFor.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        return entries.Length == 0 ? null : StripPort(entries[^1]);
    }

    /// <summary>
    /// Strips an optional ":port" suffix from one X-Forwarded-For entry.
    /// Handles "ip:port", bracketed IPv6 ("[::1]" / "[::1]:port"), and
    /// leaves a bare (unbracketed) IPv6 address untouched — it has more than
    /// one colon, so splitting on the last one would cut the address itself
    /// in half instead of removing a port.
    /// </summary>
    private static string? StripPort(string entry)
    {
        if (entry.Length == 0)
            return null;

        if (entry[0] == '[')
        {
            var closeBracket = entry.IndexOf(']');
            return closeBracket > 0 ? entry[1..closeBracket] : null;
        }

        return entry.Count(c => c == ':') == 1
            ? entry[..entry.IndexOf(':')]
            : entry;
    }

    /// <summary>
    /// The Retry-After header value (whole seconds, rounded up) for a
    /// rejected lease, or null if the limiter didn't attach a RetryAfter
    /// estimate. Program.cs's OnRejected puts this on the 429 response;
    /// dio_client.dart's RetryInterceptor reads it instead of guessing a
    /// backoff against a window length it cannot see.
    ///
    /// This is the *whole* fixed window, not the time remaining in it:
    /// FixedWindowRateLimiter's RetryAfter metadata is a constant equal to
    /// the window length, computed without regard to how far into the
    /// window the rejection happened (verified against
    /// System.Threading.RateLimiting 8.0.0 — a rejection 7s into a 10s
    /// window still reports 10s, not 3s; see
    /// RateLimiterPartitioningTests.GetRetryAfterSeconds_RejectedPartwayThroughWindow_ReturnsFullWindowNotRemaining).
    /// A caller can therefore wait up to one window longer than strictly
    /// necessary after being rejected late in a window.
    /// </summary>
    public static string? GetRetryAfterSeconds(RateLimitLease lease) =>
        lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter)
            ? ((int)Math.Ceiling(retryAfter.TotalSeconds)).ToString(CultureInfo.InvariantCulture)
            : null;
}
