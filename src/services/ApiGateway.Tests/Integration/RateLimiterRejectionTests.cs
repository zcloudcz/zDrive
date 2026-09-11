using System.Net;
using FluentAssertions;
using Xunit;

namespace ZDrive.ApiGateway.Tests.Integration;

/// <summary>
/// Exercises the "fixed" rate-limit policy (used by files-route, among
/// others) end-to-end: a caller that exceeds its window is rejected
/// immediately with a Retry-After header, rather than held in the limiter's
/// queue past the point a real client would already have given up.
///
/// The target route requires a token (AuthorizationPolicy "default"), so an
/// unauthenticated request that isn't rate-limited fails fast with 401 from
/// UseAuthorization — before ever reaching YARP/a downstream service. That
/// keeps this test fast and independent of FileService actually running,
/// the same property GatewayRoutingTests relies on.
///
/// Before this fix, QueueLimit = 10 on this policy meant an over-limit
/// request could be queued for up to the full 1-minute window instead of
/// rejected — and dio_client.dart's Dio instance has a 15s receiveTimeout,
/// far shorter than that. The client would give up first and see a
/// DioException with no response (so no status code for RetryInterceptor to
/// recognise), while the gateway kept "processing" a request nobody was
/// still waiting on. QueueLimit = 0 turns that hang into an immediate 429.
/// </summary>
[Trait("Category", "Integration")]
public sealed class RateLimiterRejectionTests
{
    [Fact]
    public async Task ExceedingTheWindow_RejectsImmediately_RatherThanHangingPastAClientTimeout()
    {
        using var factory = new GatewayFactory();
        var client = factory.CreateClient();
        // Shorter than the policy's 1-minute window: if a request were
        // queued instead of rejected, this timeout — not the assertions
        // below — is what would fail the test, the same way Dio's
        // receiveTimeout fails first against the real gateway.
        client.Timeout = TimeSpan.FromSeconds(5);

        HttpResponseMessage? rejected = null;
        // The "fixed" policy allows 100/min; the 101st request in the
        // window must be rejected rather than queued.
        for (var i = 0; i < 101; i++)
        {
            var response = await client.GetAsync("/api/v1/files/trash");
            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                rejected = response;
                break;
            }
            response.StatusCode.Should().Be(
                HttpStatusCode.Unauthorized,
                "a request within budget must fail on the missing token, not on some other problem");
        }

        rejected.Should().NotBeNull("the 101st request within the window must be rate-limited");
        rejected!.Headers.RetryAfter.Should().NotBeNull(
            "RetryInterceptor (dio_client.dart) needs this to know how long to wait, " +
            "instead of guessing a backoff against a window length it cannot see");
    }
}
