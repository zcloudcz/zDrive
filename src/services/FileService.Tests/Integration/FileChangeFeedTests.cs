using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Infrastructure.Persistence;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Tests.Integration;

/// <summary>
/// Server-side change feed (docs/adr/0001-server-side-file-change-log.md):
/// FileChangeInterceptor writes a FileChange row in the same SaveChanges
/// call as every FileNode mutation, and GetFileChangesQuery serves them as a
/// cursor-paged feed. OccurredAt is stamped by the database's own
/// clock_timestamp() (FileChangeConfiguration), not by application code, so
/// tests age a row past the 5-second hold-back with a raw SQL UPDATE against
/// the real column instead of a fake clock — that is the only way to
/// reproduce the commit-order skip bug (B1) the hold-back exists to close:
/// two rows need INDEPENDENT ages, which a single shared clock cannot give.
/// </summary>
[Trait("Category", "Integration")]
public sealed class FileChangeFeedTests : IClassFixture<FileServiceFactory>
{
    private readonly FileServiceFactory _factory;
    private readonly HttpClient _client;

    public FileChangeFeedTests(FileServiceFactory factory)
    {
        _factory = factory;
        _client = factory.CreateAuthenticatedClient();
    }

    [Fact]
    public async Task CreateFile_ProducesCreateChange()
    {
        var baseline = await GetLatestCursorAsync();

        var file = await CreateFileAsync("change-create.txt");
        await AgeSinceAsync(baseline);

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == file.Id && c.Type == "Create");
    }

    [Fact]
    public async Task CreateFolder_ProducesCreateChange()
    {
        var baseline = await GetLatestCursorAsync();

        var folder = await CreateFileAsync("change-create-folder", isFolder: true);
        await AgeSinceAsync(baseline);

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == folder.Id && c.Type == "Create");
    }

    [Fact]
    public async Task RenameFile_ProducesRenameChange()
    {
        var beforeCreate = await GetLatestCursorAsync();
        var file = await CreateFileAsync("change-rename-old.txt");
        await AgeSinceAsync(beforeCreate);
        var baseline = await GetLatestCursorAsync();

        var renameResponse = await _client.PutAsJsonAsync(
            $"/api/v1/files/{file.Id}/rename", new { newName = "change-rename-new.txt" });
        renameResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        await AgeSinceAsync(baseline);

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == file.Id && c.Type == "Rename");
    }

    [Fact]
    public async Task MoveFile_ProducesMoveChange()
    {
        var beforeCreate = await GetLatestCursorAsync();
        var folder = await CreateFileAsync("change-move-target", isFolder: true);
        var file = await CreateFileAsync("change-move-me.txt");
        await AgeSinceAsync(beforeCreate);
        var baseline = await GetLatestCursorAsync();

        var moveResponse = await _client.PutAsJsonAsync(
            $"/api/v1/files/{file.Id}/move", new { newParentId = folder.Id });
        moveResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        await AgeSinceAsync(baseline);

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == file.Id && c.Type == "Move");
    }

    [Fact]
    public async Task DeleteFile_ProducesDeleteChange()
    {
        var beforeCreate = await GetLatestCursorAsync();
        var file = await CreateFileAsync("change-delete-me.txt");
        await AgeSinceAsync(beforeCreate);
        var baseline = await GetLatestCursorAsync();

        var deleteResponse = await _client.DeleteAsync($"/api/v1/files/{file.Id}");
        deleteResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        await AgeSinceAsync(baseline);

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == file.Id && c.Type == "Delete");
    }

    [Fact]
    public async Task DeleteFolder_ProducesDeleteChangeForFolderAndEachDescendant()
    {
        var beforeCreate = await GetLatestCursorAsync();
        var folder = await CreateFileAsync("change-delete-folder", isFolder: true);
        var child = await CreateFileAsync("change-delete-child.txt", parentId: folder.Id);
        await AgeSinceAsync(beforeCreate);
        var baseline = await GetLatestCursorAsync();

        var deleteResponse = await _client.DeleteAsync($"/api/v1/files/{folder.Id}");
        deleteResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        await AgeSinceAsync(baseline);

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().Contain(c => c.FileId == folder.Id && c.Type == "Delete");
        changes.Changes.Should().Contain(c => c.FileId == child.Id && c.Type == "Delete");
    }

    [Fact]
    public async Task RestoreFile_ProducesCreateChange()
    {
        var beforeCreate = await GetLatestCursorAsync();
        var file = await CreateFileAsync("change-restore-me.txt");
        await _client.DeleteAsync($"/api/v1/files/{file.Id}");
        await AgeSinceAsync(beforeCreate);
        var baseline = await GetLatestCursorAsync();

        var restoreResponse = await _client.PostAsync($"/api/v1/files/{file.Id}/restore", null);
        restoreResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        await AgeSinceAsync(baseline);

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == file.Id && c.Type == "Create");
    }

    [Fact]
    public async Task CreateFileVersion_ProducesUpdateChange()
    {
        var beforeCreate = await GetLatestCursorAsync();
        var file = await CreateFileAsync("change-version-me.txt");
        await AgeSinceAsync(beforeCreate);
        var baseline = await GetLatestCursorAsync();

        var versionResponse = await _client.PostAsJsonAsync($"/api/v1/files/{file.Id}/versions", new
        {
            blobVersionId = "v1-hash",
            sizeBytes = 42L
        });
        versionResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        await AgeSinceAsync(baseline);

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == file.Id && c.Type == "Update");
    }

    [Fact]
    public async Task GetChanges_ExcludesOwnDevice_ButIncludesOtherAndOriginlessDevices()
    {
        var baseline = await GetLatestCursorAsync();
        var ownDevice = Guid.NewGuid();
        var otherDevice = Guid.NewGuid();

        var fromOwnDevice = await CreateFileAsync("change-origin-own.txt", deviceId: ownDevice);
        var fromOtherDevice = await CreateFileAsync("change-origin-other.txt", deviceId: otherDevice);
        var withNoOrigin = await CreateFileAsync("change-origin-none.txt");
        await AgeSinceAsync(baseline);

        var changes = await GetChangesAsync(baseline, deviceId: ownDevice);

        changes.Changes.Should().NotContain(c => c.FileId == fromOwnDevice.Id);
        changes.Changes.Should().Contain(c => c.FileId == fromOtherDevice.Id);
        changes.Changes.Should().Contain(c => c.FileId == withNoOrigin.Id);
    }

    [Fact]
    public async Task GetChanges_AllRemainingRowsAreOwnDevice_StillAdvancesCursor()
    {
        // Review finding B2: the origin filter used to run before the cursor
        // was fixed, so a page that turned out empty (everything left was
        // this device's own write) echoed the request cursor back — the
        // device would re-scan the same growing own-origin tail forever.
        // Excluding a row must not stop it from moving the cursor.
        var baseline = await GetLatestCursorAsync();
        var device = Guid.NewGuid();

        await CreateFileAsync("change-own-device-only.txt", deviceId: device);
        await AgeSinceAsync(baseline);
        var expectedCursor = await GetLatestCursorAsync();

        var page = await GetChangesAsync(baseline, deviceId: device);
        page.Changes.Should().BeEmpty();
        page.NextCursor.Should().Be(expectedCursor);

        // A second poll from that cursor must not re-read the same row.
        var secondPage = await GetChangesAsync(page.NextCursor, deviceId: device);
        secondPage.Changes.Should().BeEmpty();
        secondPage.NextCursor.Should().Be(page.NextCursor);
    }

    [Fact]
    public async Task GetChanges_AnotherUsersChanges_NeverAppear()
    {
        var baseline = await GetLatestCursorAsync();

        var strangerClient = _factory.CreateAuthenticatedClient(Guid.NewGuid(), Guid.NewGuid());
        var strangerFileResponse = await strangerClient.PostAsJsonAsync("/api/v1/files", new
        {
            name = "change-stranger.txt",
            isFolder = false
        });
        strangerFileResponse.StatusCode.Should().Be(HttpStatusCode.Created);
        var strangerFile = (await strangerFileResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var myFile = await CreateFileAsync("change-mine.txt");
        await AgeSinceAsync(baseline);

        var changes = await GetChangesAsync(baseline);

        changes.Changes.Should().NotContain(c => c.FileId == strangerFile.Id);
        changes.Changes.Should().Contain(c => c.FileId == myFile.Id);
    }

    [Fact]
    public async Task GetChanges_Paging_RespectsLimitAndReturnsNextCursorAndHasMore()
    {
        var baseline = await GetLatestCursorAsync();

        for (var i = 0; i < 5; i++)
            await CreateFileAsync($"change-page-{Guid.NewGuid()}.txt");
        await AgeSinceAsync(baseline);

        var firstPage = await GetChangesAsync(baseline, limit: 2);
        firstPage.Changes.Should().HaveCount(2);
        firstPage.HasMore.Should().BeTrue();
        firstPage.NextCursor.Should().Be(firstPage.Changes[^1].Id);

        var secondPage = await GetChangesAsync(firstPage.NextCursor, limit: 2);
        secondPage.Changes.Should().HaveCount(2);
        secondPage.HasMore.Should().BeTrue();

        var thirdPage = await GetChangesAsync(secondPage.NextCursor, limit: 2);
        thirdPage.Changes.Should().HaveCount(1);
        thirdPage.HasMore.Should().BeFalse();
        thirdPage.NextCursor.Should().Be(secondPage.NextCursor + 1);

        // Nothing left: an empty page keeps the request's own cursor rather than resetting it.
        var fourthPage = await GetChangesAsync(thirdPage.NextCursor, limit: 2);
        fourthPage.Changes.Should().BeEmpty();
        fourthPage.HasMore.Should().BeFalse();
        fourthPage.NextCursor.Should().Be(thirdPage.NextCursor);
    }

    [Fact]
    public async Task GetChanges_ChangeWithinHoldBackWindow_ExcludedUntilAgedPastFiveSeconds()
    {
        var baseline = await GetLatestCursorAsync();

        var file = await CreateFileAsync("change-holdback.txt");

        // Freshly inserted: clock_timestamp() stamped it "now", still within
        // the 5s hold-back — nothing to see yet, cursor stays put.
        var tooSoon = await GetChangesAsync(baseline);
        tooSoon.Changes.Should().BeEmpty();
        tooSoon.NextCursor.Should().Be(baseline);

        // Age it past the window with a real UPDATE against the DB clock's
        // own column — not a fake app-level clock — and it becomes visible.
        await AgeSinceAsync(baseline);
        var afterAging = await GetChangesAsync(baseline);
        afterAging.Changes.Should().ContainSingle(c => c.FileId == file.Id);
    }

    [Fact]
    public async Task GetChanges_OlderRowNotYetAged_IsNotSkippedByAYoungerHigherIdRow()
    {
        // Reproduces review finding B1: a per-row time filter lets a
        // higher-id row through while holding back a lower-id row that is
        // still "too young", and advances the cursor past the lower-id row
        // forever once its own age would otherwise have made it visible. The
        // fix holds back everything from the first too-young row onward —
        // a prefix of the id order, not a per-row filter.
        var baseline = await GetLatestCursorAsync();

        var changeA = await CreateFileAsync("change-order-a.txt"); // lower id, inserted first
        var changeB = await CreateFileAsync("change-order-b.txt"); // higher id, inserted second

        // Age only B: simulates A's transaction still being "slow" (not yet
        // aged past the hold-back) while B's has already aged past it.
        await AgeChangeAsync(changeB.Id);

        var page = await GetChangesAsync(baseline);
        page.Changes.Should().BeEmpty();
        page.NextCursor.Should().Be(baseline);

        // Now age A too: both become visible, still in id order.
        await AgeChangeAsync(changeA.Id);
        var afterAgingBoth = await GetChangesAsync(baseline);
        afterAgingBoth.Changes.Select(c => c.FileId).Should().Equal(changeA.Id, changeB.Id);
    }

    private async Task<long> GetLatestCursorAsync()
    {
        // Earlier tests in this class already age every row they create
        // before making their own assertions, so a full drain from 0 with a
        // generous limit reliably finds the current high-water mark.
        var page = await GetChangesAsync(cursor: 0, limit: 1000);
        while (page.HasMore)
            page = await GetChangesAsync(cursor: page.NextCursor, limit: 1000);
        return page.NextCursor;
    }

    /// <summary>
    /// Moves every change row inserted after <paramref name="sinceCursor"/>
    /// (i.e. this test's own rows) past the 5-second hold-back, by rewriting
    /// occurred_at directly through a raw SQL UPDATE. OccurredAt now comes
    /// from the database's clock_timestamp() default (FileChangeConfiguration),
    /// not from application code, so there is no in-process clock left to fake.
    /// </summary>
    private Task AgeSinceAsync(long sinceCursor) =>
        ExecuteSqlAsync($"UPDATE files.file_changes SET occurred_at = occurred_at - interval '6 seconds' WHERE id > {sinceCursor}");

    /// <summary>Ages only the change row(s) for one file — lets a test control two rows' ages independently.</summary>
    private Task AgeChangeAsync(Guid fileId) =>
        ExecuteSqlAsync($"UPDATE files.file_changes SET occurred_at = occurred_at - interval '6 seconds' WHERE file_id = {fileId}");

    private async Task ExecuteSqlAsync(FormattableString sql)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<FileDbContext>();
        await db.Database.ExecuteSqlInterpolatedAsync(sql);
    }

    private async Task<FileDto> CreateFileAsync(
        string name, bool isFolder = false, Guid? parentId = null, Guid? deviceId = null)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/files")
        {
            Content = JsonContent.Create(new { name, isFolder, parentId })
        };
        if (deviceId.HasValue)
            request.Headers.Add("X-Device-Id", deviceId.Value.ToString());

        var response = await _client.SendAsync(request);
        response.StatusCode.Should().Be(HttpStatusCode.Created, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
    }

    private async Task<FileChangesPageDto> GetChangesAsync(long cursor = 0, int? limit = null, Guid? deviceId = null)
    {
        var url = $"/api/v1/files/changes?cursor={cursor}" + (limit.HasValue ? $"&limit={limit}" : "");
        var request = new HttpRequestMessage(HttpMethod.Get, url);
        if (deviceId.HasValue)
            request.Headers.Add("X-Device-Id", deviceId.Value.ToString());

        var response = await _client.SendAsync(request);
        response.StatusCode.Should().Be(HttpStatusCode.OK, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<ApiResponse<FileChangesPageDto>>())!.Data!;
    }
}
