using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Options;
using ZDrive.FileService.Domain.Enums;
using ZDrive.Shared.Auth;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Tests.Integration;

/// <summary>
/// Covers the write endpoints under shares/link/{token} (Package A):
/// info, folders, upload-grant, files/{id}/versions and items/{id}. Unlike
/// SharedDownloadFlowTests's StorageService counterpart, this suite mints a
/// ShareUploadReceipt itself with FileServiceFactory.TestShareGrantKey
/// rather than driving StorageService — the receipt IS the trust boundary
/// FileService's versions endpoint is supposed to enforce, so signing one
/// directly here is exactly what proves that boundary, not a shortcut
/// around it.
/// </summary>
[Trait("Category", "Integration")]
public sealed class ShareWriteFlowTests : IClassFixture<FileServiceFactory>
{
    private readonly FileServiceFactory _factory;
    private readonly HttpClient _client;
    private readonly HttpClient _anon;
    private readonly byte[] _key;

    public ShareWriteFlowTests(FileServiceFactory factory)
    {
        _factory = factory;
        // A fresh owner per test instance (xUnit creates one instance per
        // [Fact]/[Theory] case) — not FileServiceFactory.TestUserId/TestTenantId,
        // which every test in the whole assembly would otherwise share along
        // with the one Testcontainers database. UploadGrant_101stPendingNode
        // in particular leaves 100 version-less nodes behind for its owner;
        // sharing an owner with any other upload-grant test would make the
        // pair order-dependent (whichever runs second sees the other's count).
        _client = factory.CreateAuthenticatedClient(Guid.NewGuid(), Guid.NewGuid());
        _anon = factory.CreateClient();
        _key = Convert.FromBase64String(FileServiceFactory.TestShareGrantKey);
    }

    private static void AssertPublicShareCacheHeaders(HttpResponseMessage response)
    {
        response.Headers.CacheControl!.NoStore.Should().BeTrue();
        response.Headers.CacheControl.Private.Should().BeTrue();
        response.Headers.Vary.Should().Contain("X-Share-Grant");
    }

    private async Task<FileDto> CreateFileAsync(string name, Guid? parentId = null, bool isFolder = false, long? sizeBytes = null)
    {
        var response = await _client.PostAsJsonAsync("/api/v1/files", new { name, isFolder, parentId, sizeBytes });
        return (await response.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
    }

    private async Task<ShareDto> CreateShareAsync(Guid fileId, Permission permission = Permission.Write, bool allowDelete = false, string? password = null)
    {
        var response = await _client.PostAsJsonAsync("/api/v1/shares", new { fileId, permission, allowDelete, password });
        return (await response.Content.ReadFromJsonAsync<ApiResponse<ShareDto>>())!.Data!;
    }

    private string MakeReceipt(Guid fileId, string manifestHash, long sizeBytes, DateTimeOffset? expiresAt = null) =>
        ShareUploadReceipt.Create(
            new ShareUploadReceipt.Payload(fileId, manifestHash, sizeBytes, expiresAt ?? DateTimeOffset.UtcNow.AddMinutes(15)), _key);

    [Fact]
    public async Task Info_ReturnsPermissionAllowDeleteRootAndQuota()
    {
        var root = await CreateFileAsync("info-root", isFolder: true);
        var share = await CreateShareAsync(root.Id, Permission.Write, allowDelete: true);

        var response = await _anon.GetAsync($"/api/v1/shares/link/{share.LinkToken}/info");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        AssertPublicShareCacheHeaders(response);
        var info = (await response.Content.ReadFromJsonAsync<ApiResponse<ShareInfoDto>>())!.Data!;
        info.Permission.Should().Be("Write");
        info.AllowDelete.Should().BeTrue();
        info.Root.Id.Should().Be(root.Id);
        info.Quota.Should().NotBeNull();
        info.Quota!.LimitBytes.Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task Info_ReadOnlyLink_QuotaIsNull()
    {
        // A Read link's visitor has no reason to learn how full the owner's
        // account is — quota is only surfaced to a Write (or Admin) link.
        var root = await CreateFileAsync("info-readonly-root", isFolder: true);
        var share = await CreateShareAsync(root.Id, Permission.Read);

        var response = await _anon.GetAsync($"/api/v1/shares/link/{share.LinkToken}/info");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var info = (await response.Content.ReadFromJsonAsync<ApiResponse<ShareInfoDto>>())!.Data!;
        info.Quota.Should().BeNull();
    }

    [Fact]
    public async Task UploadGrant_101stPendingNode_ReturnsTooManyRequests()
    {
        var root = await CreateFileAsync("pending-root", isFolder: true);
        var share = await CreateShareAsync(root.Id);

        for (var i = 0; i < 100; i++)
        {
            var response = await _anon.PostAsJsonAsync(
                $"/api/v1/shares/link/{share.LinkToken}/upload-grant",
                new { fileName = $"pending-{i}.bin", sizeBytes = 1L, overwrite = false });
            response.StatusCode.Should().Be(HttpStatusCode.OK);
        }

        var overCap = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/upload-grant",
            new { fileName = "pending-101.bin", sizeBytes = 1L, overwrite = false });

        overCap.StatusCode.Should().Be((HttpStatusCode)429);
        (await overCap.Content.ReadAsStringAsync()).Should().Contain("TOO_MANY_PENDING_UPLOADS");
    }

    [Fact]
    public async Task AnonymousResponses_NeverExposeOwnerIdsOrBlobPath()
    {
        var root = await CreateFileAsync("leak-root", isFolder: true);
        var file = await CreateFileAsync("leak-file.txt", parentId: root.Id);
        var share = await CreateShareAsync(root.Id);

        // The authenticated FileDto for `file` carries the real owner ids —
        // use those as the needles.
        file.UserId.Should().NotBe(Guid.Empty);
        var userIdText = file.UserId.ToString();
        var tenantIdText = file.TenantId.ToString();

        var infoBody = await (await _anon.GetAsync($"/api/v1/shares/link/{share.LinkToken}/info")).Content.ReadAsStringAsync();
        infoBody.Should().NotContain(userIdText).And.NotContain(tenantIdText);

        var metadataBody = await (await _anon.GetAsync($"/api/v1/shares/link/{share.LinkToken}")).Content.ReadAsStringAsync();
        metadataBody.Should().NotContain(userIdText).And.NotContain(tenantIdText).And.NotContain(share.LinkToken);

        var childrenBody = await (await _anon.GetAsync($"/api/v1/shares/link/{share.LinkToken}/children")).Content.ReadAsStringAsync();
        childrenBody.Should().NotContain(userIdText).And.NotContain(tenantIdText);

        var folderBody = await (await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/folders", new { name = "leak-sub" })).Content.ReadAsStringAsync();
        folderBody.Should().NotContain(userIdText).And.NotContain(tenantIdText);
    }

    [Fact]
    public async Task CreateSharedFolder_HappyPath_NameCollision409_ParentOutside404()
    {
        var root = await CreateFileAsync("folders-root", isFolder: true);
        var outside = await CreateFileAsync("folders-outside", isFolder: true);
        var share = await CreateShareAsync(root.Id);

        var created = await _anon.PostAsJsonAsync($"/api/v1/shares/link/{share.LinkToken}/folders", new { name = "sub" });
        created.StatusCode.Should().Be(HttpStatusCode.OK);
        AssertPublicShareCacheHeaders(created);
        var createdFolder = (await created.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
        createdFolder.IsFolder.Should().BeTrue();

        var collision = await _anon.PostAsJsonAsync($"/api/v1/shares/link/{share.LinkToken}/folders", new { name = "sub" });
        collision.StatusCode.Should().Be(HttpStatusCode.Conflict);

        var outsideParent = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/folders", new { parentId = outside.Id, name = "nope" });
        outsideParent.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task UploadGrant_NewFile_OverwriteReuse_Collisions_AndSingleFileShare()
    {
        var root = await CreateFileAsync("grant-root", isFolder: true);
        var share = await CreateShareAsync(root.Id);
        var outside = await CreateFileAsync("grant-outside", isFolder: true);

        // New file: creates a placeholder node and returns a grant bound to it.
        var grantResp = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/upload-grant",
            new { fileName = "new.bin", sizeBytes = 100L, overwrite = false });
        grantResp.StatusCode.Should().Be(HttpStatusCode.OK);
        AssertPublicShareCacheHeaders(grantResp);
        var grant = (await grantResp.Content.ReadFromJsonAsync<ApiResponse<ShareUploadGrantResultDto>>())!.Data!;
        grant.MaxBytes.Should().Be(100);
        ShareUploadGrant.TryValidate(grant.Grant, _key, DateTimeOffset.UtcNow, out var payload).Should().BeTrue();
        payload.FileId.Should().Be(grant.FileId);

        // Same name without overwrite -> 409.
        var collision = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/upload-grant",
            new { fileName = "new.bin", sizeBytes = 1L, overwrite = false });
        collision.StatusCode.Should().Be(HttpStatusCode.Conflict);

        // Same name with overwrite -> reuses the existing node id.
        var overwrite = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/upload-grant",
            new { fileName = "new.bin", sizeBytes = 50L, overwrite = true });
        overwrite.StatusCode.Should().Be(HttpStatusCode.OK);
        var overwriteGrant = (await overwrite.Content.ReadFromJsonAsync<ApiResponse<ShareUploadGrantResultDto>>())!.Data!;
        overwriteGrant.FileId.Should().Be(grant.FileId);

        // A folder occupies the name -> 409 even with overwrite=true.
        await _client.PostAsJsonAsync("/api/v1/files", new { name = "folder-name", isFolder = true, parentId = root.Id });
        var folderCollision = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/upload-grant",
            new { fileName = "folder-name", sizeBytes = 1L, overwrite = true });
        folderCollision.StatusCode.Should().Be(HttpStatusCode.Conflict);

        // Parent outside the share -> 404.
        var outsideParent = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/upload-grant",
            new { parentId = outside.Id, fileName = "x.bin", sizeBytes = 1L, overwrite = false });
        outsideParent.StatusCode.Should().Be(HttpStatusCode.NotFound);

        // A share whose root IS a single file: the grant always targets it.
        var rootFile = await CreateFileAsync("single.bin", sizeBytes: 10);
        var fileShare = await CreateShareAsync(rootFile.Id);
        var singleFileGrant = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{fileShare.LinkToken}/upload-grant", new { sizeBytes = 20L, overwrite = true });
        singleFileGrant.StatusCode.Should().Be(HttpStatusCode.OK);
        var singleGrantResult = (await singleFileGrant.Content.ReadFromJsonAsync<ApiResponse<ShareUploadGrantResultDto>>())!.Data!;
        singleGrantResult.FileId.Should().Be(rootFile.Id);
    }

    [Fact]
    public async Task Versions_ValidReceipt_RecordsVersionAppearsInChildrenAndChangeFeed()
    {
        var root = await CreateFileAsync("versions-root", isFolder: true);
        var file = await CreateFileAsync("doc.txt", parentId: root.Id);
        var share = await CreateShareAsync(root.Id);
        var manifestHash = new string('c', 64);
        var receipt = MakeReceipt(file.Id, manifestHash, 77);

        var response = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/files/{file.Id}/versions", new { receipt });

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        AssertPublicShareCacheHeaders(response);
        var updated = (await response.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
        updated.ManifestHash.Should().Be(manifestHash);
        updated.SizeBytes.Should().Be(77);

        var children = await _anon.GetFromJsonAsync<ApiResponse<List<FileDto>>>(
            $"/api/v1/shares/link/{share.LinkToken}/children");
        children!.Data.Should().ContainSingle(f => f.Id == file.Id && f.ManifestHash == manifestHash);

        // The change feed deliberately withholds rows younger than 5s (see
        // CLAUDE.md "File change log" / docs/adr/0001) so a reader can never
        // observe them out of commit order — poll instead of asserting
        // immediately.
        await PollUntilChangeAppearsAsync(file.Id, TimeSpan.FromSeconds(10));
    }

    private async Task PollUntilChangeAppearsAsync(Guid fileId, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (true)
        {
            var changes = await _client.GetFromJsonAsync<ApiResponse<FileChangesPageDto>>("/api/v1/files/changes");
            if (changes!.Data!.Changes.Any(c => c.FileId == fileId))
                return;

            if (DateTime.UtcNow >= deadline)
                throw new TimeoutException($"File change for {fileId} did not appear within {timeout}.");

            await Task.Delay(250);
        }
    }

    [Fact]
    public async Task Versions_InvalidOrMismatchedOrReplayedReceipts()
    {
        var root = await CreateFileAsync("versions-root-2", isFolder: true);
        var file = await CreateFileAsync("doc2.txt", parentId: root.Id);
        var otherFile = await CreateFileAsync("doc3.txt", parentId: root.Id);
        var share = await CreateShareAsync(root.Id);
        var manifestHash = new string('d', 64);

        // Receipt minted for a different file -> 404.
        var wrongFileReceipt = MakeReceipt(otherFile.Id, manifestHash, 5);
        var wrongFile = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/files/{file.Id}/versions", new { receipt = wrongFileReceipt });
        wrongFile.StatusCode.Should().Be(HttpStatusCode.NotFound);

        // Expired receipt -> 404.
        var expiredReceipt = MakeReceipt(file.Id, manifestHash, 5, DateTimeOffset.UtcNow.AddMinutes(-1));
        var expired = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/files/{file.Id}/versions", new { receipt = expiredReceipt });
        expired.StatusCode.Should().Be(HttpStatusCode.NotFound);

        // Tampered receipt -> 404, and the body never echoes it back.
        var validReceipt = MakeReceipt(file.Id, manifestHash, 5);
        var tampered = GrantTampering.FlipSignatureBit(validReceipt);
        var tamperedResponse = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/files/{file.Id}/versions", new { receipt = tampered });
        tamperedResponse.StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await tamperedResponse.Content.ReadAsStringAsync()).Should().NotContain(tampered);

        // A download grant or an upload grant presented as a receipt -> 404 (domain separation).
        var downloadGrant = ShareDownloadGrant.Create(
            new ShareDownloadGrant.Payload(Guid.NewGuid(), Guid.NewGuid(), file.Id, manifestHash, DateTimeOffset.UtcNow.AddHours(1)), _key);
        var downloadAsReceipt = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/files/{file.Id}/versions", new { receipt = downloadGrant });
        downloadAsReceipt.StatusCode.Should().Be(HttpStatusCode.NotFound);

        var uploadGrant = ShareUploadGrant.Create(
            new ShareUploadGrant.Payload(Guid.NewGuid(), Guid.NewGuid(), file.Id, 5, DateTimeOffset.UtcNow.AddHours(1), QuotaRemainingBytes: 5000), _key);
        var uploadAsReceipt = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/files/{file.Id}/versions", new { receipt = uploadGrant });
        uploadAsReceipt.StatusCode.Should().Be(HttpStatusCode.NotFound);

        // A replayed valid receipt records exactly one version.
        var first = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/files/{file.Id}/versions", new { receipt = validReceipt });
        first.StatusCode.Should().Be(HttpStatusCode.OK);
        var replay = await _anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/files/{file.Id}/versions", new { receipt = validReceipt });
        replay.StatusCode.Should().Be(HttpStatusCode.OK);

        var versionsResponse = await _client.GetFromJsonAsync<ApiResponse<List<FileVersionDto>>>($"/api/v1/files/{file.Id}/versions");
        versionsResponse!.Data!.Count(v => v.ManifestHash == manifestHash).Should().Be(1);
    }

    [Fact]
    public async Task ReadOnlyLink_ForbiddenOnEveryWriteEndpoint()
    {
        var root = await CreateFileAsync("readonly-root", isFolder: true);
        var file = await CreateFileAsync("readonly.txt", parentId: root.Id);
        var share = await CreateShareAsync(root.Id, Permission.Read);
        var receipt = MakeReceipt(file.Id, new string('e', 64), 1);

        (await _anon.PostAsJsonAsync($"/api/v1/shares/link/{share.LinkToken}/folders", new { name = "x" }))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _anon.PostAsJsonAsync($"/api/v1/shares/link/{share.LinkToken}/upload-grant", new { fileName = "x.bin", sizeBytes = 1L, overwrite = false }))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _anon.PostAsJsonAsync($"/api/v1/shares/link/{share.LinkToken}/files/{file.Id}/versions", new { receipt }))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _anon.DeleteAsync($"/api/v1/shares/link/{share.LinkToken}/items/{file.Id}"))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Delete_AllowDeleteRules_RootForbidden_OutsideNotFound()
    {
        var root = await CreateFileAsync("delete-root", isFolder: true);
        var file = await CreateFileAsync("delete-me.txt", parentId: root.Id);
        var outside = await CreateFileAsync("delete-outside.txt");

        // Write link without AllowDelete -> 403.
        var writeOnly = await CreateShareAsync(root.Id, Permission.Write, allowDelete: false);
        (await _anon.DeleteAsync($"/api/v1/shares/link/{writeOnly.LinkToken}/items/{file.Id}"))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);

        // Write + AllowDelete -> soft-deletes into the owner's trash.
        var deletable = await CreateShareAsync(root.Id, Permission.Write, allowDelete: true);
        var deleteResponse = await _anon.DeleteAsync($"/api/v1/shares/link/{deletable.LinkToken}/items/{file.Id}");
        deleteResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        (await deleteResponse.Content.ReadFromJsonAsync<ApiResponse<bool>>())!.Data.Should().BeTrue();

        var trashResponse = await _client.GetAsync("/api/v1/files/trash");
        trashResponse.StatusCode.Should().Be(HttpStatusCode.OK, await trashResponse.Content.ReadAsStringAsync());
        var trash = await trashResponse.Content.ReadFromJsonAsync<ApiResponse<PagedResult<FileDto>>>();
        trash!.Data!.Items.Should().Contain(f => f.Id == file.Id);

        // The shared root itself can never be deleted through its own link.
        var rootDelete = await _anon.DeleteAsync($"/api/v1/shares/link/{deletable.LinkToken}/items/{root.Id}");
        rootDelete.StatusCode.Should().Be(HttpStatusCode.Forbidden);

        // An id that exists but is outside the share -> 404, not 403.
        var outsideDelete = await _anon.DeleteAsync($"/api/v1/shares/link/{deletable.LinkToken}/items/{outside.Id}");
        outsideDelete.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task PasswordProtectedLink_ForbiddenOnEveryEndpoint()
    {
        var root = await CreateFileAsync("pw-root", isFolder: true);
        var file = await CreateFileAsync("pw.txt", parentId: root.Id);
        var share = await CreateShareAsync(root.Id, Permission.Write, allowDelete: true, password: "hunter2");
        var receipt = MakeReceipt(file.Id, new string('f', 64), 1);

        (await _anon.GetAsync($"/api/v1/shares/link/{share.LinkToken}/info")).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _anon.PostAsJsonAsync($"/api/v1/shares/link/{share.LinkToken}/folders", new { name = "x" }))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _anon.PostAsJsonAsync($"/api/v1/shares/link/{share.LinkToken}/upload-grant", new { fileName = "x.bin", sizeBytes = 1L, overwrite = false }))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _anon.PostAsJsonAsync($"/api/v1/shares/link/{share.LinkToken}/files/{file.Id}/versions", new { receipt }))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await _anon.DeleteAsync($"/api/v1/shares/link/{share.LinkToken}/items/{file.Id}"))
            .StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Quota_OwnerAtLimit_UploadGrantReturns413()
    {
        // A DERIVED host with a tiny default quota — never mutate the shared
        // factory's own StorageOptions, or every other test in this (and any
        // other) class sharing it would see the same tiny limit.
        var quotaFactory = _factory.WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
            services.PostConfigure<StorageOptions>(options => options.DefaultUserQuotaBytes = 10)));

        var owner = quotaFactory.CreateClient();
        owner.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _factory.CreateTestToken(Guid.NewGuid(), Guid.NewGuid()));
        var anon = quotaFactory.CreateClient();

        var rootResponse = await owner.PostAsJsonAsync("/api/v1/files", new { name = "quota-root", isFolder = true });
        var root = (await rootResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
        var shareResponse = await owner.PostAsJsonAsync("/api/v1/shares", new { fileId = root.Id, permission = Permission.Write });
        var share = (await shareResponse.Content.ReadFromJsonAsync<ApiResponse<ShareDto>>())!.Data!;

        var response = await anon.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/upload-grant",
            new { fileName = "too-big.bin", sizeBytes = 1000L, overwrite = false });

        response.StatusCode.Should().Be(HttpStatusCode.RequestEntityTooLarge);
        var body = await response.Content.ReadAsStringAsync();
        body.Should().Contain("QUOTA_EXCEEDED");
    }
}
