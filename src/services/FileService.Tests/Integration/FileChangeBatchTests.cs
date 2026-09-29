using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using MediatR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Queries.GetFileChangeBatch;
using ZDrive.FileService.Infrastructure.Persistence;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Tests.Integration;

/// <summary>
/// The global change feed used by in-process consumers (photo ingest). The
/// read semantics are shared with the per-user feed (FileChangeFeedReader), so
/// FileChangeFeedTests cover hold-back and lock behaviour; these cover what is
/// specific to the global query: all users, one entry per file, current node state.
/// </summary>
[Trait("Category", "Integration")]
public sealed class FileChangeBatchTests : IClassFixture<FileServiceFactory>
{
    private readonly FileServiceFactory _factory;

    public FileChangeBatchTests(FileServiceFactory factory) => _factory = factory;

    [Fact]
    public async Task GetFileChangeBatch_ChangesFromTwoUsers_ReturnsBothWithTheirOwnIds()
    {
        var (aliceId, aliceTenant) = (Guid.NewGuid(), Guid.NewGuid());
        var (bobId, bobTenant) = (Guid.NewGuid(), Guid.NewGuid());
        var alice = await CreateAsync(_factory.CreateAuthenticatedClient(aliceId, aliceTenant), "alice.jpg");
        var bob = await CreateAsync(_factory.CreateAuthenticatedClient(bobId, bobTenant), "bob.jpg");
        await AgeAllAsync();

        var files = await ReadAllAsync();

        files.Should().Contain(f => f.FileId == alice.Id && f.UserId == aliceId && f.TenantId == aliceTenant);
        files.Should().Contain(f => f.FileId == bob.Id && f.UserId == bobId && f.TenantId == bobTenant);
    }

    [Fact]
    public async Task GetFileChangeBatch_SeveralChangesToOneFile_ReturnsOneEntryWithCurrentState()
    {
        var client = _factory.CreateAuthenticatedClient(Guid.NewGuid(), Guid.NewGuid());
        var file = await CreateAsync(client, "before.jpg");
        (await client.PutAsJsonAsync($"/api/v1/files/{file.Id}/rename", new { newName = "after.jpg" }))
            .StatusCode.Should().Be(HttpStatusCode.OK);
        await AgeAllAsync();

        var files = await ReadAllAsync();

        var entry = files.Should().ContainSingle(f => f.FileId == file.Id, "Create and Rename collapse into one entry").Subject;
        entry.Node!.Name.Should().Be("after.jpg", "the snapshot is the CURRENT state, not the state at the first change");
        entry.Node.MimeType.Should().Be("image/jpeg");
        entry.Node.IsDeleted.Should().BeFalse();
    }

    [Fact]
    public async Task GetFileChangeBatch_TrashedFile_ReportsDeletedAndPurgedFileReportsNoNode()
    {
        var client = _factory.CreateAuthenticatedClient(Guid.NewGuid(), Guid.NewGuid());
        var trashed = await CreateAsync(client, "trashed.jpg");
        var purged = await CreateAsync(client, "purged.jpg");
        await client.DeleteAsync($"/api/v1/files/{trashed.Id}");
        await client.DeleteAsync($"/api/v1/files/{purged.Id}");
        (await client.DeleteAsync("/api/v1/files/trash")).StatusCode.Should().Be(HttpStatusCode.OK); // hard-deletes both
        var stillTrashed = await CreateAsync(client, "stays-in-trash.jpg");
        await client.DeleteAsync($"/api/v1/files/{stillTrashed.Id}");
        await AgeAllAsync();

        var files = await ReadAllAsync();

        files.Single(f => f.FileId == stillTrashed.Id).Node!.IsDeleted.Should().BeTrue();
        files.Single(f => f.FileId == purged.Id).Node.Should().BeNull("EmptyTrash removed the node; consumers must treat that as hidden");
    }

    [Fact]
    public async Task GetFileChangeBatch_RowYoungerThanHoldBack_IsNotReturnedYet()
    {
        var client = _factory.CreateAuthenticatedClient(Guid.NewGuid(), Guid.NewGuid());
        await AgeAllAsync();
        var cursorBefore = (await ReadPageAsync(0, 1000, drain: true)).NextCursor;

        var fresh = await CreateAsync(client, "fresh.jpg"); // deliberately NOT aged

        var page = await ReadPageAsync(cursorBefore, 1000);
        page.Files.Should().NotContain(f => f.FileId == fresh.Id);
        page.NextCursor.Should().Be(cursorBefore, "the cursor must not move past a row that is still held back");
    }

    [Fact]
    public async Task GetFileChangeBatch_LimitSmallerThanBacklog_PagesWithoutLosingFiles()
    {
        var client = _factory.CreateAuthenticatedClient(Guid.NewGuid(), Guid.NewGuid());
        var created = new List<Guid>();
        for (var i = 0; i < 5; i++)
            created.Add((await CreateAsync(client, $"paged-{i}.jpg")).Id);
        await AgeAllAsync();

        var seen = new List<Guid>();
        long cursor = 0;
        PageResult page;
        do
        {
            page = await ReadPageAsync(cursor, 3);
            seen.AddRange(page.Files.Select(f => f.FileId));
            cursor = page.NextCursor;
        } while (page.HasMore);

        seen.Should().Contain(created);
    }

    [Fact]
    public async Task GetFileChangeBatch_InvalidLimit_FailsValidation()
    {
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();

        var act = async () => await mediator.Send(new GetFileChangeBatchQuery(0, 0));

        await act.Should().ThrowAsync<FluentValidation.ValidationException>();
    }

    // ---------------------------------------------------------------- helpers

    private sealed record PageResult(List<ChangedFileDto> Files, long NextCursor, bool HasMore);

    private async Task<PageResult> ReadPageAsync(long cursor, int limit, bool drain = false)
    {
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();
        var all = new List<ChangedFileDto>();
        var page = await mediator.Send(new GetFileChangeBatchQuery(cursor, limit));
        all.AddRange(page.Files);
        while (drain && page.HasMore)
        {
            page = await mediator.Send(new GetFileChangeBatchQuery(page.NextCursor, limit));
            all.AddRange(page.Files);
        }
        return new PageResult(all, page.NextCursor, page.HasMore);
    }

    private async Task<List<ChangedFileDto>> ReadAllAsync() => (await ReadPageAsync(0, 1000, drain: true)).Files;

    private static async Task<FileDto> CreateAsync(HttpClient client, string name)
    {
        var response = await client.PostAsJsonAsync("/api/v1/files", new { name, isFolder = false, mimeType = "image/jpeg", manifestHash = "abc123" });
        response.StatusCode.Should().Be(HttpStatusCode.Created, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
    }

    private async Task AgeAllAsync()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<FileDbContext>();
        await db.Database.ExecuteSqlRawAsync(
            "UPDATE files.file_changes SET occurred_at = occurred_at - interval '10 seconds' WHERE occurred_at > now() - interval '5 seconds'");
    }
}
