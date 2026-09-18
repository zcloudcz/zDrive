using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZDrive.Shared.Auth;
using ZDrive.Shared.DTOs;
using ZDrive.StorageService.Api.Controllers;
using ZDrive.StorageService.Application.DTOs;
using ZDrive.StorageService.Domain.Enums;
using ZDrive.StorageService.Infrastructure.Persistence;

namespace ZDrive.StorageService.Tests.Integration;

/// <summary>
/// Covers the anonymous /api/v1/storage/shared/upload/* endpoints, the
/// upload-direction twin of SharedDownloadFlowTests. The grant is minted
/// directly here with StorageServiceFactory.TestShareGrantKey — same
/// reasoning as SharedDownloadFlowTests: this suite proves StorageService's
/// OWN validation and accounting, not FileService's grant-minting logic.
/// </summary>
[Trait("Category", "Integration")]
public sealed class SharedUploadFlowTests : IClassFixture<StorageServiceFactory>
{
    private readonly StorageServiceFactory _factory;
    private readonly HttpClient _anon;
    private readonly byte[] _key;

    public SharedUploadFlowTests(StorageServiceFactory factory)
    {
        _factory = factory;
        _anon = factory.CreateClient();
        _key = Convert.FromBase64String(StorageServiceFactory.TestShareGrantKey);
    }

    private string MakeGrant(Guid tenantId, Guid ownerId, Guid fileId, long maxBytes, long quotaRemaining = 1_000_000_000) =>
        ShareUploadGrant.Create(
            new ShareUploadGrant.Payload(tenantId, ownerId, fileId, maxBytes, DateTimeOffset.UtcNow.AddHours(1), quotaRemaining), _key);

    private Task<HttpResponseMessage> InitShared(string grant, string fileName, int totalChunks)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/storage/shared/upload/init")
        { Content = JsonContent.Create(new { fileName, totalChunks }) };
        request.Headers.Add("X-Share-Grant", grant);
        return _anon.SendAsync(request);
    }

    private Task<HttpResponseMessage> PutShared(string grant, Guid sessionId, int index, byte[] bytes, bool chunkedTransfer = false)
    {
        var content = new StreamContent(new MemoryStream(bytes));
        content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        var request = new HttpRequestMessage(HttpMethod.Put, $"/api/v1/storage/shared/upload/{sessionId}/chunk/{index}")
        { Content = content };
        if (chunkedTransfer)
            request.Headers.TransferEncodingChunked = true; // no Content-Length sent
        request.Headers.Add("X-Share-Grant", grant);
        request.Headers.Add("X-Chunk-Hash", $"hash-{index}");
        return _anon.SendAsync(request);
    }

    private Task<HttpResponseMessage> CompleteShared(string grant, Guid sessionId)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, $"/api/v1/storage/shared/upload/{sessionId}/complete");
        request.Headers.Add("X-Share-Grant", grant);
        return _anon.SendAsync(request);
    }

    private Task<HttpResponseMessage> AbortShared(string grant, Guid sessionId)
    {
        var request = new HttpRequestMessage(HttpMethod.Delete, $"/api/v1/storage/shared/upload/{sessionId}");
        request.Headers.Add("X-Share-Grant", grant);
        return _anon.SendAsync(request);
    }

    [Fact]
    public async Task FullAnonymousUpload_TwoChunks_ReceiptValidatesAndBytesDownloadBackIdentically()
    {
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();
        var fileId = Guid.NewGuid();
        var chunk0 = new byte[1024];
        var chunk1 = new byte[512];
        Random.Shared.NextBytes(chunk0);
        Random.Shared.NextBytes(chunk1);
        var grant = MakeGrant(tenantId, ownerId, fileId, maxBytes: 4096);

        var init = await InitShared(grant, "anon.bin", 2);
        init.StatusCode.Should().Be(HttpStatusCode.OK);
        var sessionId = (await init.Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!.SessionId;

        (await PutShared(grant, sessionId, 0, chunk0)).StatusCode.Should().Be(HttpStatusCode.OK);
        (await PutShared(grant, sessionId, 1, chunk1)).StatusCode.Should().Be(HttpStatusCode.OK);

        var completeResponse = await CompleteShared(grant, sessionId);
        completeResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var complete = (await completeResponse.Content.ReadFromJsonAsync<ApiResponse<SharedUploadCompleteDto>>())!.Data!;
        complete.TotalSize.Should().Be(1024 + 512);

        ShareUploadReceipt.TryValidate(complete.Receipt, _key, DateTimeOffset.UtcNow, out var receipt).Should().BeTrue();
        receipt.FileId.Should().Be(fileId);
        receipt.ManifestHash.Should().Be(complete.ManifestHash);
        receipt.SizeBytes.Should().Be(complete.TotalSize);

        // Bytes download back identically through the existing public download flow.
        var downloadGrant = ShareDownloadGrant.Create(
            new ShareDownloadGrant.Payload(tenantId, ownerId, fileId, complete.ManifestHash, DateTimeOffset.UtcNow.AddHours(1)), _key);
        var manifestRequest = new HttpRequestMessage(HttpMethod.Get, "/api/v1/storage/shared/manifest");
        manifestRequest.Headers.Add("X-Share-Grant", downloadGrant);
        var manifestResponse = await _anon.SendAsync(manifestRequest);
        manifestResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var manifest = (await manifestResponse.Content.ReadFromJsonAsync<ApiResponse<ManifestDto>>())!.Data!;

        foreach (var chunk in manifest.Chunks)
        {
            var chunkRequest = new HttpRequestMessage(HttpMethod.Get, $"/api/v1/storage/shared/chunk/{chunk.Hash}/bytes");
            chunkRequest.Headers.Add("X-Share-Grant", downloadGrant);
            var chunkResponse = await _anon.SendAsync(chunkRequest);
            chunkResponse.StatusCode.Should().Be(HttpStatusCode.OK);
            var bytes = await chunkResponse.Content.ReadAsByteArrayAsync();
            bytes.Should().BeEquivalentTo(chunk.Index == 0 ? chunk0 : chunk1);
        }
    }

    [Fact]
    public async Task InitUpload_NoOrTamperedOrDownloadGrant_ReturnsNotFound()
    {
        (await InitShared("", "x.bin", 1)).StatusCode.Should().Be(HttpStatusCode.NotFound);

        var grant = MakeGrant(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), 100);
        var tampered = GrantTampering.FlipSignatureBit(grant);
        (await InitShared(tampered, "x.bin", 1)).StatusCode.Should().Be(HttpStatusCode.NotFound);

        var downloadGrant = ShareDownloadGrant.Create(
            new ShareDownloadGrant.Payload(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), new string('a', 64), DateTimeOffset.UtcNow.AddHours(1)), _key);
        (await InitShared(downloadGrant, "x.bin", 1)).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task ChunkOrCompleteOrAbort_GrantForDifferentFile_ReturnsNotFound()
    {
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();
        var fileId = Guid.NewGuid();
        var grant = MakeGrant(tenantId, ownerId, fileId, maxBytes: 4096);
        var sessionId = (await (await InitShared(grant, "bound.bin", 1))
            .Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!.SessionId;

        // A grant for a DIFFERENT fileId (same tenant/owner) must not reach this session.
        var otherFileGrant = MakeGrant(tenantId, ownerId, Guid.NewGuid(), maxBytes: 4096);

        (await PutShared(otherFileGrant, sessionId, 0, new byte[10])).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await CompleteShared(otherFileGrant, sessionId)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await AbortShared(otherFileGrant, sessionId)).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task AuthenticatedAndSharedEndpoints_RefuseEachOthersSessions()
    {
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();
        var fileId = Guid.NewGuid();
        var authClient = _factory.CreateClient();
        authClient.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", _factory.CreateAccessToken(ownerId, tenantId));

        // Shared session created via the grant — the authenticated endpoint
        // for the SAME owner/file must still refuse it (IsShared mismatch).
        var grant = MakeGrant(tenantId, ownerId, fileId, maxBytes: 4096);
        var sharedSessionId = (await (await InitShared(grant, "shared.bin", 1))
            .Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!.SessionId;

        var authChunkRequest = new HttpRequestMessage(HttpMethod.Put, $"/api/v1/storage/upload/{sharedSessionId}/chunk/0")
        { Content = new ByteArrayContent(new byte[10]) };
        authChunkRequest.Headers.Add("X-Chunk-Hash", "hash-0");
        (await authClient.SendAsync(authChunkRequest)).StatusCode.Should().Be(HttpStatusCode.NotFound);

        // Authenticated session — the shared endpoint must refuse it even
        // with a grant that happens to carry the same tenant/owner/file ids.
        var authInit = await authClient.PostAsJsonAsync("/api/v1/storage/upload/init", new { fileId, fileName = "auth.bin", totalChunks = 1 });
        var authSessionId = (await authInit.Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!.SessionId;

        (await PutShared(grant, authSessionId, 0, new byte[10])).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Chunk_ChunkedTransferEncoding_CountedTowardCap()
    {
        var grant = MakeGrant(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), maxBytes: 100);
        var sessionId = (await (await InitShared(grant, "chunked.bin", 1))
            .Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!.SessionId;

        // Sent with Transfer-Encoding: chunked, so the request carries no
        // Content-Length at all — the cap must still be enforced from the
        // bytes actually stored, not bypassed by omitting the header.
        var over = await PutShared(grant, sessionId, 0, new byte[200], chunkedTransfer: true);

        over.StatusCode.Should().Be(HttpStatusCode.RequestEntityTooLarge);
    }

    [Fact]
    public async Task Chunk_RetryOfSameIndex_DoesNotDoubleCountOrTrigger413()
    {
        var grant = MakeGrant(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), maxBytes: 100);
        var sessionId = (await (await InitShared(grant, "retry.bin", 1))
            .Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!.SessionId;

        (await PutShared(grant, sessionId, 0, new byte[80])).StatusCode.Should().Be(HttpStatusCode.OK);
        // A legitimate retry of the SAME index (e.g. client-side timeout then
        // resend) replaces its own contribution instead of adding to it.
        var retry = await PutShared(grant, sessionId, 0, new byte[80]);

        retry.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Chunk_OverCap_ChunkIsNotStored()
    {
        var grant = MakeGrant(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), maxBytes: 50);
        var initResponse = await InitShared(grant, "overcap.bin", 1);
        var sessionId = (await initResponse.Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!.SessionId;

        (await PutShared(grant, sessionId, 0, new byte[100])).StatusCode.Should().Be(HttpStatusCode.RequestEntityTooLarge);

        // The rejected chunk must not have been left behind — completing
        // with it "present" would otherwise succeed despite the 413.
        (await CompleteShared(grant, sessionId)).StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Complete_SessionMaxBytesLoweredAfterChunksAccepted_Returns413AndAbortsSession()
    {
        // The per-chunk check in UploadChunk cannot be exercised through the
        // API alone to prove Complete's OWN re-check (any chunk sequence that
        // would fail Complete's total check already fails a chunk PUT first
        // — see the two accounting tests above). So: accept both chunks
        // honestly under a generous cap, then shrink MaxBytes directly
        // through the DbContext (as if the grant's budget had been computed
        // tighter), and prove Complete refuses to promote a session that is
        // now over cap rather than trusting the chunk-time bookkeeping.
        var grant = MakeGrant(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), maxBytes: 1000);
        var initResponse = await InitShared(grant, "shrunk-cap.bin", 2);
        var sessionId = (await initResponse.Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!.SessionId;

        (await PutShared(grant, sessionId, 0, new byte[60])).StatusCode.Should().Be(HttpStatusCode.OK);
        (await PutShared(grant, sessionId, 1, new byte[60])).StatusCode.Should().Be(HttpStatusCode.OK);

        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<StorageDbContext>();
            var session = await db.UploadSessions.SingleAsync(s => s.Id == sessionId);
            session.MaxBytes = 50; // below the 120 already accepted
            await db.SaveChangesAsync();
        }

        var complete = await CompleteShared(grant, sessionId);
        complete.StatusCode.Should().Be(HttpStatusCode.RequestEntityTooLarge);

        using var readScope = _factory.Services.CreateScope();
        var readDb = readScope.ServiceProvider.GetRequiredService<StorageDbContext>();
        var finalStatus = await readDb.UploadSessions.AsNoTracking()
            .Where(s => s.Id == sessionId).Select(s => s.Status).SingleAsync();
        finalStatus.Should().Be(UploadSessionStatus.Aborted);
    }

    [Fact]
    public async Task InitUpload_SharedBudgetExhausted_Returns413()
    {
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();

        // First grant consumes almost the whole quota headroom with a still-open session.
        var firstGrant = MakeGrant(tenantId, ownerId, Guid.NewGuid(), maxBytes: 900, quotaRemaining: 1000);
        (await InitShared(firstGrant, "first.bin", 1)).StatusCode.Should().Be(HttpStatusCode.OK);

        // A second grant against the SAME owner's remaining budget (same
        // quotaRemaining, since the grants were minted independently but the
        // owner's real headroom hasn't changed) pushes the 24h in-flight sum past it.
        var secondGrant = MakeGrant(tenantId, ownerId, Guid.NewGuid(), maxBytes: 200, quotaRemaining: 1000);
        var second = await InitShared(secondGrant, "second.bin", 1);

        second.StatusCode.Should().Be(HttpStatusCode.RequestEntityTooLarge);
    }

    [Fact]
    public async Task InitUpload_CompletedSessionDoesNotCountAgainstBudget_ButAnOpenOneDoes()
    {
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();

        // First session consumes 900 of a 1000 budget, then COMPLETES — its
        // bytes are now visible to the real (FileService-side) quota once a
        // receipt is recorded, so they must stop counting against this
        // in-flight budget, or a legitimate heavy uploader gets refused at
        // roughly half their real headroom for no reason.
        var firstGrant = MakeGrant(tenantId, ownerId, Guid.NewGuid(), maxBytes: 900, quotaRemaining: 1000);
        var firstInit = await InitShared(firstGrant, "completed.bin", 1);
        var firstSessionId = (await firstInit.Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!.SessionId;
        (await PutShared(firstGrant, firstSessionId, 0, new byte[900])).StatusCode.Should().Be(HttpStatusCode.OK);
        (await CompleteShared(firstGrant, firstSessionId)).StatusCode.Should().Be(HttpStatusCode.OK);

        // A second grant for 200 now fits: 0 (nothing still open) + 200 <= 1000.
        var secondGrant = MakeGrant(tenantId, ownerId, Guid.NewGuid(), maxBytes: 200, quotaRemaining: 1000);
        (await InitShared(secondGrant, "second.bin", 1)).StatusCode.Should().Be(HttpStatusCode.OK);

        // But that second session is still OPEN (Active), so a THIRD grant
        // that would push the open sum past budget is still refused: 200 + 900 > 1000.
        var thirdGrant = MakeGrant(tenantId, ownerId, Guid.NewGuid(), maxBytes: 900, quotaRemaining: 1000);
        (await InitShared(thirdGrant, "third.bin", 1)).StatusCode.Should().Be(HttpStatusCode.RequestEntityTooLarge);
    }

    [Fact]
    public async Task InitUpload_ParallelInits_OnlyAsManyAsFitTheBudgetSucceed()
    {
        var tenantId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();
        const long budget = 1000;
        const long perGrantMaxBytes = 300; // floor(1000/300) = 3 should succeed, out of 5 attempts
        var grants = Enumerable.Range(0, 5)
            .Select(_ => MakeGrant(tenantId, ownerId, Guid.NewGuid(), perGrantMaxBytes, budget))
            .ToList();

        var results = await Task.WhenAll(grants.Select(g => InitShared(g, "parallel.bin", 1)));

        results.Count(r => r.StatusCode == HttpStatusCode.OK).Should().Be(3);
        results.Count(r => r.StatusCode == HttpStatusCode.RequestEntityTooLarge).Should().Be(2);
    }
}
