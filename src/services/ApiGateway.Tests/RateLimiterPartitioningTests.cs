using System.Security.Claims;
using FluentAssertions;
using Xunit;
using ZDrive.Shared.Auth;

namespace ZDrive.ApiGateway.Tests;

/// <summary>
/// The gateway's "fixed" and "auth" rate-limit policies key their fixed
/// window off <see cref="RateLimiterPartitioning.GetPartitionKey"/> (see
/// Program.cs). Previously the limiter was global, so a single large upload
/// (~256 chunk requests for 1 GB) would 429 itself halfway through and eat
/// every other user's budget at the same time — these tests pin down the
/// per-caller partitioning that fixes that, including the case the change
/// had to make a deliberate call on: auth-route requests are unauthenticated
/// by design and so have no user id to key on.
/// </summary>
public sealed class RateLimiterPartitioningTests
{
    private static ClaimsPrincipal UserWithId(string userId) =>
        new(new ClaimsIdentity([new Claim(JwtConstants.UserIdClaim, userId)]));

    private static readonly ClaimsPrincipal Anonymous = new(new ClaimsIdentity());

    [Fact]
    public void GetPartitionKey_AuthenticatedUser_ReturnsUserId()
    {
        var user = UserWithId("11111111-1111-1111-1111-111111111111");

        RateLimiterPartitioning.GetPartitionKey(user, "203.0.113.5")
            .Should().Be("11111111-1111-1111-1111-111111111111");
    }

    [Fact]
    public void GetPartitionKey_TwoDifferentUsers_ReturnDifferentKeys()
    {
        var userA = UserWithId("11111111-1111-1111-1111-111111111111");
        var userB = UserWithId("22222222-2222-2222-2222-222222222222");

        RateLimiterPartitioning.GetPartitionKey(userA, "203.0.113.5")
            .Should().NotBe(
                RateLimiterPartitioning.GetPartitionKey(userB, "203.0.113.5"),
                "one user's upload must not share a rate-limit budget with another user's, " +
                "even calling from the same IP");
    }

    [Fact]
    public void GetPartitionKey_UnauthenticatedRequest_FallsBackToIpAddress()
    {
        RateLimiterPartitioning.GetPartitionKey(Anonymous, "198.51.100.7")
            .Should().Be(
                "198.51.100.7",
                "the auth-route (login/register) is unauthenticated by design, " +
                "so it has no user id to key on");
    }

    [Fact]
    public void GetPartitionKey_UnauthenticatedRequestWithNoIpAddress_ReturnsUnknown()
    {
        RateLimiterPartitioning.GetPartitionKey(Anonymous, null)
            .Should().Be("unknown");
    }
}
