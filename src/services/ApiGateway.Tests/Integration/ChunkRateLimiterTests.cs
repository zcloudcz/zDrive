using System.Net;
using FluentAssertions;
using Xunit;

namespace ZDrive.ApiGateway.Tests.Integration;

/// <summary>
/// Chunk PUTs (storage-upload-route, /api/v1/storage/upload/**) get their own
/// "chunk" rate-limit policy instead of sharing "fixed" with every other
/// route (see Program.cs). Before this, a single large upload — ~256 chunk
/// PUTs for 1 GB — shared its budget with that same user's file list,
/// thumbnails, sync status, etc., so an upload in progress could 429 the rest
/// of the app for its whole duration.
///
/// This test exhausts the "chunk" policy's own budget (600/min) and then
/// checks an interactive call (files-route, "fixed", 100/min) still succeeds
/// (fails on the missing token, not a 429) — the only way to tell a genuinely
/// separate policy from one that merely looks separate in configuration but
/// still shares a partition/counter at runtime.
/// </summary>
[Trait("Category", "Integration")]
public sealed class ChunkRateLimiterTests
{
    [Fact]
    public async Task ChunkRouteExceedingItsOwnWindow_DoesNotThrottleTheInteractiveFixedPolicy()
    {
        using var factory = new GatewayFactory();
        var client = factory.CreateClient();
        client.Timeout = TimeSpan.FromSeconds(30);

        HttpResponseMessage? chunkRejected = null;
        // The "chunk" policy allows 600/min; the 601st request in the window
        // must be rejected rather than queued.
        for (var i = 0; i < 601; i++)
        {
            var response = await client.PutAsync(
                "/api/v1/storage/upload/11111111-1111-1111-1111-111111111111/chunk/0",
                new ByteArrayContent([]));
            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                chunkRejected = response;
                break;
            }
            response.StatusCode.Should().Be(
                HttpStatusCode.Unauthorized,
                "a chunk PUT within budget must fail on the missing token, not on some other problem");
        }

        chunkRejected.Should().NotBeNull("the 601st chunk PUT within the window must be rate-limited");

        // If the chunk route still shared its counter with "fixed" (the bug
        // this policy split fixes), this call would also be rejected: the
        // same partition key (this client has no user id, so it falls back
        // to its own address) would already show hundreds of hits against a
        // 100/min limit.
        var interactive = await client.GetAsync("/api/v1/files/trash");
        interactive.StatusCode.Should().Be(
            HttpStatusCode.Unauthorized,
            "the \"fixed\" policy's own 100/min budget is untouched by chunk traffic, " +
            "so this must fail on the missing token rather than 429");
    }
}
