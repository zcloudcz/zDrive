using System.Security.Claims;
using System.Threading.RateLimiting;
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

    [Fact]
    public void GetRetryAfterSeconds_RejectedLease_ReturnsWholeSecondsRoundedUp()
    {
        // A real FixedWindowRateLimiter (rather than a hand-rolled fake lease)
        // so this pins down actual .NET behaviour: does a rejected lease
        // really carry a RetryAfter estimate for a fixed window? (It does —
        // MetadataName.RetryAfter, verified against System.Threading.RateLimiting
        // 8.0.0 before writing Program.cs's OnRejected around it.)
        using var limiter = new FixedWindowRateLimiter(new FixedWindowRateLimiterOptions
        {
            PermitLimit = 1,
            Window = TimeSpan.FromSeconds(30),
            QueueLimit = 0,
            AutoReplenishment = false,
        });
        limiter.AttemptAcquire(1).IsAcquired.Should().BeTrue("the first permit must succeed for this test to mean anything");

        var rejected = limiter.AttemptAcquire(1);

        rejected.IsAcquired.Should().BeFalse();
        RateLimiterPartitioning.GetRetryAfterSeconds(rejected).Should().Be("30");
    }

    [Fact]
    public async Task GetRetryAfterSeconds_RejectedPartwayThroughWindow_ReturnsFullWindowNotRemaining()
    {
        // AutoReplenishment=true (a real timer, unlike the other tests here)
        // is what makes this case meaningful: rejecting immediately after
        // acquiring the only permit can't distinguish "reports the full
        // window" from "reports the time remaining", because at t=0 those
        // are the same number. Waiting partway into the window before
        // rejecting is the only way to tell them apart — and the doc comment
        // on GetRetryAfterSeconds says it reports the *whole* window, so this
        // must still read the window length (4s), not the ~2s actually left.
        using var limiter = new FixedWindowRateLimiter(new FixedWindowRateLimiterOptions
        {
            PermitLimit = 1,
            Window = TimeSpan.FromSeconds(4),
            QueueLimit = 0,
            AutoReplenishment = true,
        });
        limiter.AttemptAcquire(1).IsAcquired.Should().BeTrue("the first permit must succeed for this test to mean anything");

        await Task.Delay(TimeSpan.FromSeconds(2));

        var rejected = limiter.AttemptAcquire(1);

        rejected.IsAcquired.Should().BeFalse();
        RateLimiterPartitioning.GetRetryAfterSeconds(rejected).Should().Be(
            "4",
            "a rejection 2s into a 4s window still reports the full 4s, not the ~2s actually left");
    }

    [Fact]
    public void GetRetryAfterSeconds_AcquiredLeaseCarriesNoRetryAfterMetadata_ReturnsNull()
    {
        using var limiter = new FixedWindowRateLimiter(new FixedWindowRateLimiterOptions
        {
            PermitLimit = 1,
            Window = TimeSpan.FromSeconds(30),
            QueueLimit = 0,
            AutoReplenishment = false,
        });

        var acquired = limiter.AttemptAcquire(1);

        acquired.IsAcquired.Should().BeTrue();
        RateLimiterPartitioning.GetRetryAfterSeconds(acquired).Should().BeNull();
    }
}
