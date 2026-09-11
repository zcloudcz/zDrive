using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Xunit;
using ZDrive.FileService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Tests.Integration;

/// <summary>
/// Server-side change feed (docs/adr/0001-server-side-file-change-log.md):
/// FileChangeInterceptor writes a FileChange row in the same SaveChanges
/// call as every FileNode mutation, and GetFileChangesQuery serves them as a
/// cursor-paged feed. All tests advance the factory's ManualTimeProvider by
/// more than 5 seconds after making a change — the feed withholds anything
/// younger than that (commit-order hold-back), so nothing would be visible
/// otherwise.
/// </summary>
[Trait("Category", "Integration")]
public sealed class FileChangeFeedTests : IClassFixture<FileServiceFactory>
{
    private static readonly TimeSpan HoldBack = TimeSpan.FromSeconds(5);

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
        AdvancePastHoldBack();

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == file.Id && c.Type == "Create");
    }

    [Fact]
    public async Task CreateFolder_ProducesCreateChange()
    {
        var baseline = await GetLatestCursorAsync();

        var folder = await CreateFileAsync("change-create-folder", isFolder: true);
        AdvancePastHoldBack();

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == folder.Id && c.Type == "Create");
    }

    [Fact]
    public async Task RenameFile_ProducesRenameChange()
    {
        var file = await CreateFileAsync("change-rename-old.txt");
        AdvancePastHoldBack();
        var baseline = await GetLatestCursorAsync();

        var renameResponse = await _client.PutAsJsonAsync(
            $"/api/v1/files/{file.Id}/rename", new { newName = "change-rename-new.txt" });
        renameResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        AdvancePastHoldBack();

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == file.Id && c.Type == "Rename");
    }

    [Fact]
    public async Task MoveFile_ProducesMoveChange()
    {
        var folder = await CreateFileAsync("change-move-target", isFolder: true);
        var file = await CreateFileAsync("change-move-me.txt");
        AdvancePastHoldBack();
        var baseline = await GetLatestCursorAsync();

        var moveResponse = await _client.PutAsJsonAsync(
            $"/api/v1/files/{file.Id}/move", new { newParentId = folder.Id });
        moveResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        AdvancePastHoldBack();

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == file.Id && c.Type == "Move");
    }

    [Fact]
    public async Task DeleteFile_ProducesDeleteChange()
    {
        var file = await CreateFileAsync("change-delete-me.txt");
        AdvancePastHoldBack();
        var baseline = await GetLatestCursorAsync();

        var deleteResponse = await _client.DeleteAsync($"/api/v1/files/{file.Id}");
        deleteResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        AdvancePastHoldBack();

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == file.Id && c.Type == "Delete");
    }

    [Fact]
    public async Task DeleteFolder_ProducesDeleteChangeForFolderAndEachDescendant()
    {
        var folder = await CreateFileAsync("change-delete-folder", isFolder: true);
        var child = await CreateFileAsync("change-delete-child.txt", parentId: folder.Id);
        AdvancePastHoldBack();
        var baseline = await GetLatestCursorAsync();

        var deleteResponse = await _client.DeleteAsync($"/api/v1/files/{folder.Id}");
        deleteResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        AdvancePastHoldBack();

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().Contain(c => c.FileId == folder.Id && c.Type == "Delete");
        changes.Changes.Should().Contain(c => c.FileId == child.Id && c.Type == "Delete");
    }

    [Fact]
    public async Task RestoreFile_ProducesCreateChange()
    {
        var file = await CreateFileAsync("change-restore-me.txt");
        await _client.DeleteAsync($"/api/v1/files/{file.Id}");
        AdvancePastHoldBack();
        var baseline = await GetLatestCursorAsync();

        var restoreResponse = await _client.PostAsync($"/api/v1/files/{file.Id}/restore", null);
        restoreResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        AdvancePastHoldBack();

        var changes = await GetChangesAsync(baseline);
        changes.Changes.Should().ContainSingle(c => c.FileId == file.Id && c.Type == "Create");
    }

    [Fact]
    public async Task CreateFileVersion_ProducesUpdateChange()
    {
        var file = await CreateFileAsync("change-version-me.txt");
        AdvancePastHoldBack();
        var baseline = await GetLatestCursorAsync();

        var versionResponse = await _client.PostAsJsonAsync($"/api/v1/files/{file.Id}/versions", new
        {
            blobVersionId = "v1-hash",
            sizeBytes = 42L
        });
        versionResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        AdvancePastHoldBack();

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
        AdvancePastHoldBack();

        var changes = await GetChangesAsync(baseline, deviceId: ownDevice);

        changes.Changes.Should().NotContain(c => c.FileId == fromOwnDevice.Id);
        changes.Changes.Should().Contain(c => c.FileId == fromOtherDevice.Id);
        changes.Changes.Should().Contain(c => c.FileId == withNoOrigin.Id);
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
        AdvancePastHoldBack();

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
        AdvancePastHoldBack();

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
    public async Task GetChanges_WithinHoldBackWindow_ExcludedUntilClockAdvancesPastFiveSeconds()
    {
        var baseline = await GetLatestCursorAsync();

        var file = await CreateFileAsync("change-holdback.txt");

        // Not advanced yet: the change is younger than the 5s hold-back.
        var tooSoon = await GetChangesAsync(baseline);
        tooSoon.Changes.Should().NotContain(c => c.FileId == file.Id);

        // Still short of the window.
        _factory.TimeProvider.Advance(TimeSpan.FromSeconds(4));
        var stillTooSoon = await GetChangesAsync(baseline);
        stillTooSoon.Changes.Should().NotContain(c => c.FileId == file.Id);

        // Past 5s total: now visible.
        _factory.TimeProvider.Advance(TimeSpan.FromSeconds(2));
        var afterHoldBack = await GetChangesAsync(baseline);
        afterHoldBack.Changes.Should().Contain(c => c.FileId == file.Id);
    }

    private void AdvancePastHoldBack() => _factory.TimeProvider.Advance(HoldBack + TimeSpan.FromSeconds(1));

    private async Task<long> GetLatestCursorAsync()
    {
        // Earlier tests in this class already advanced the clock well past
        // their own changes' hold-back window, so a full drain from 0 with a
        // generous limit reliably finds the current high-water mark.
        var page = await GetChangesAsync(cursor: 0, limit: 1000);
        while (page.HasMore)
            page = await GetChangesAsync(cursor: page.NextCursor, limit: 1000);
        return page.NextCursor;
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
