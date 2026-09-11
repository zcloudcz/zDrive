using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using MediatR;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZDrive.FileService.Application.Commands.CreateFile;
using ZDrive.FileService.Application.DTOs;
using ZDrive.Shared.DTOs;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class FileFlowTests : IClassFixture<FileServiceFactory>
{
    private readonly HttpClient _client;
    private readonly FileServiceFactory _factory;

    public FileFlowTests(FileServiceFactory factory)
    {
        _client = factory.CreateAuthenticatedClient();
        _factory = factory;
    }

    [Fact]
    public async Task CreateFolder_CreateFileInside_ListChildren_FullFlow()
    {
        // Create folder
        var folderResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "Documents",
            isFolder = true
        });
        folderResponse.StatusCode.Should().Be(HttpStatusCode.Created);

        var folderResult = await folderResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>();
        folderResult.Should().NotBeNull();
        folderResult!.Success.Should().BeTrue();
        folderResult.Data!.Name.Should().Be("Documents");
        folderResult.Data.IsFolder.Should().BeTrue();

        var folderId = folderResult.Data.Id;

        // Create file inside folder
        var fileResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "readme.txt",
            parentId = folderId,
            isFolder = false,
            sizeBytes = 1024L,
            mimeType = "text/plain",
            blobPath = "/tenant/user/readme.txt"
        });
        fileResponse.StatusCode.Should().Be(HttpStatusCode.Created);

        var fileResult = await fileResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>();
        fileResult!.Success.Should().BeTrue();
        fileResult.Data!.Name.Should().Be("readme.txt");
        fileResult.Data.ParentId.Should().Be(folderId);

        // List children of the folder
        var listResponse = await _client.GetAsync($"/api/v1/files/{folderId}/children?page=1&pageSize=50");
        listResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var listResult = await listResponse.Content.ReadFromJsonAsync<ApiResponse<PagedResult<FileDto>>>();
        listResult!.Success.Should().BeTrue();
        listResult.Data!.TotalCount.Should().Be(1);
        listResult.Data.Items.Should().ContainSingle(f => f.Name == "readme.txt");
    }

    [Fact]
    public async Task ListRootChildren_ReturnsTopLevelItems()
    {
        // A folder created with no parent lives at the root.
        var rootFolder = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "RootLevelFolder",
            isFolder = true
        });
        rootFolder.StatusCode.Should().Be(HttpStatusCode.Created);

        // The root listing route (no GUID) must surface it.
        var listResponse = await _client.GetAsync("/api/v1/files/root/children?page=1&pageSize=50");
        listResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var listResult = await listResponse.Content.ReadFromJsonAsync<ApiResponse<PagedResult<FileDto>>>();
        listResult!.Success.Should().BeTrue();
        listResult.Data!.Items.Should().Contain(f => f.Name == "RootLevelFolder");
    }

    [Fact]
    public async Task RenameFile_UpdatesName()
    {
        // Create file
        var createResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "old-name.txt",
            isFolder = false
        });
        var createResult = await createResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>();
        var fileId = createResult!.Data!.Id;

        // Rename
        var renameResponse = await _client.PutAsJsonAsync($"/api/v1/files/{fileId}/rename", new
        {
            newName = "new-name.txt"
        });
        renameResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var renameResult = await renameResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>();
        renameResult!.Data!.Name.Should().Be("new-name.txt");

        // Verify via GET
        var getResponse = await _client.GetAsync($"/api/v1/files/{fileId}");
        var getResult = await getResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>();
        getResult!.Data!.Name.Should().Be("new-name.txt");
    }

    [Fact]
    public async Task MoveFile_BetweenFolders()
    {
        // Create two folders
        var folder1Response = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "FolderA-Move",
            isFolder = true
        });
        var folder1 = (await folder1Response.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var folder2Response = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "FolderB-Move",
            isFolder = true
        });
        var folder2 = (await folder2Response.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        // Create file in folder1
        var fileResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "moveable.txt",
            parentId = folder1.Id,
            isFolder = false
        });
        var file = (await fileResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
        file.ParentId.Should().Be(folder1.Id);

        // Move to folder2
        var moveResponse = await _client.PutAsJsonAsync($"/api/v1/files/{file.Id}/move", new
        {
            newParentId = folder2.Id
        });
        moveResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var moveResult = (await moveResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
        moveResult.ParentId.Should().Be(folder2.Id);
    }

    [Fact]
    public async Task DeleteFile_AppearsInTrash_Restore_BackInPlace()
    {
        // Create file
        var createResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "trashable.txt",
            isFolder = false
        });
        var file = (await createResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        // Delete (soft)
        var deleteResponse = await _client.DeleteAsync($"/api/v1/files/{file.Id}");
        deleteResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        // Verify it's gone from normal listing (should 404)
        var getResponse = await _client.GetAsync($"/api/v1/files/{file.Id}");
        getResponse.StatusCode.Should().Be(HttpStatusCode.NotFound);

        // Appears in trash
        var trashResponse = await _client.GetAsync("/api/v1/files/trash?page=1&pageSize=200");
        var trashResult = await trashResponse.Content.ReadFromJsonAsync<ApiResponse<PagedResult<FileDto>>>();
        trashResult!.Data!.Items.Should().Contain(f => f.Id == file.Id);

        // Restore
        var restoreResponse = await _client.PostAsync($"/api/v1/files/{file.Id}/restore", null);
        restoreResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        // Verify it's back
        var getAfterRestore = await _client.GetAsync($"/api/v1/files/{file.Id}");
        getAfterRestore.StatusCode.Should().Be(HttpStatusCode.OK);

        var restored = (await getAfterRestore.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
        restored.IsDeleted.Should().BeFalse();
    }

    [Fact]
    public async Task EmptyTrash_PermanentlyRemovesItems()
    {
        // Create and delete a file
        var createResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "permanent-delete.txt",
            isFolder = false
        });
        var file = (await createResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        await _client.DeleteAsync($"/api/v1/files/{file.Id}");

        // Empty trash
        var emptyResponse = await _client.DeleteAsync("/api/v1/files/trash");
        emptyResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var emptyResult = await emptyResponse.Content.ReadFromJsonAsync<ApiResponse<int>>();
        emptyResult!.Data.Should().BeGreaterOrEqualTo(1);

        // Should not appear in trash anymore
        var trashResponse = await _client.GetAsync("/api/v1/files/trash?page=1&pageSize=200");
        var trashResult = await trashResponse.Content.ReadFromJsonAsync<ApiResponse<PagedResult<FileDto>>>();
        trashResult!.Data!.Items.Should().NotContain(f => f.Id == file.Id);

        // Restore should fail
        var restoreResponse = await _client.PostAsync($"/api/v1/files/{file.Id}/restore", null);
        restoreResponse.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task CreateDuplicate_Returns409()
    {
        var payload = new { name = "unique-file.txt", isFolder = false };

        var first = await _client.PostAsJsonAsync("/api/v1/files", payload);
        first.StatusCode.Should().Be(HttpStatusCode.Created);

        var second = await _client.PostAsJsonAsync("/api/v1/files", payload);
        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    // The next three tests pin PR #12 review round 3, B1 (server side): a
    // sibling name that differs only by case is the same directory entry on
    // NTFS and default APFS, so create/rename/move must reject it exactly
    // like an exact-case duplicate, not treat it as a distinct name.

    [Fact]
    public async Task CreateDuplicate_CaseOnlyDifference_Returns409()
    {
        var first = await _client.PostAsJsonAsync("/api/v1/files", new { name = "Photos", isFolder = true });
        first.StatusCode.Should().Be(HttpStatusCode.Created);

        var second = await _client.PostAsJsonAsync("/api/v1/files", new { name = "photos", isFolder = true });
        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task RenameFile_CaseOnlyCollisionWithSibling_Returns409()
    {
        var sibling = await _client.PostAsJsonAsync("/api/v1/files", new { name = "Docs", isFolder = true });
        (await sibling.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!.Id.Should().NotBeEmpty();

        var toRename = await _client.PostAsJsonAsync("/api/v1/files", new { name = "Other", isFolder = true });
        var toRenameId = (await toRename.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!.Id;

        // Renaming "Other" to "docs" collides with the existing "Docs" only by case.
        var renameResponse = await _client.PutAsJsonAsync($"/api/v1/files/{toRenameId}/rename", new
        {
            newName = "docs"
        });
        renameResponse.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task MoveFile_CaseOnlyCollisionInTargetFolder_Returns409()
    {
        var targetFolder = await _client.PostAsJsonAsync("/api/v1/files", new { name = "TargetFolder-CaseMove", isFolder = true });
        var target = (await targetFolder.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var existing = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "Report.docx",
            parentId = target.Id,
            isFolder = false
        });
        existing.StatusCode.Should().Be(HttpStatusCode.Created);

        var moving = await _client.PostAsJsonAsync("/api/v1/files", new { name = "report.docx", isFolder = false });
        var movingFile = (await moving.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        // Moving "report.docx" into TargetFolder-CaseMove collides with the
        // existing "Report.docx" there only by case.
        var moveResponse = await _client.PutAsJsonAsync($"/api/v1/files/{movingFile.Id}/move", new
        {
            newParentId = target.Id
        });
        moveResponse.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task RestoreFile_CaseOnlyCollisionWithLiveSibling_Returns409()
    {
        // RestoreFileCommandHandler has no sibling pre-check (unlike create/
        // rename/move) — restore relies entirely on the unique index on
        // (tenant_id, user_id, parent_id, name_normalized) WHERE is_deleted =
        // false to catch this. Before ExceptionHandlingMiddleware mapped a
        // unique-violation DbUpdateException to 409, that raw constraint
        // violation surfaced as a 500 (PR #12 review round 4, C2).
        var original = await _client.PostAsJsonAsync("/api/v1/files", new { name = "Report", isFolder = false });
        original.StatusCode.Should().Be(HttpStatusCode.Created);
        var originalFile = (await original.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var deleteResponse = await _client.DeleteAsync($"/api/v1/files/{originalFile.Id}");
        deleteResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        // A case-only namesake now lives live at the same spot the restore
        // would put "Report" back into.
        var sibling = await _client.PostAsJsonAsync("/api/v1/files", new { name = "report", isFolder = false });
        sibling.StatusCode.Should().Be(HttpStatusCode.Created);

        var restoreResponse = await _client.PostAsync($"/api/v1/files/{originalFile.Id}/restore", null);
        restoreResponse.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task CreateDuplicate_CaseOnlyDifferenceUnderTurkishCulture_Returns409NotServerError()
    {
        // f.Name.ToLower() is translated to SQL lower(), which folds "I" to
        // "i" regardless of .NET culture. Before CreateFileCommandHandler
        // used ToLowerInvariant() for the request side, request.Name.ToLower()
        // ran under whatever culture happened to be current — under Turkish,
        // "I" folds to "ı" (dotless), not "i". A duplicate check comparing
        // "fıle-tr.txt" (Turkish fold) against "file-tr.txt" (SQL fold) never
        // matches, so the handler would let the insert proceed and the
        // database's own case-insensitive unique index would reject it with
        // a raw constraint-violation error — surfacing as 500, not the clean
        // 409 a real name collision should produce (PR #12 review round 4).
        //
        // This used to drive the create through the HttpClient, relying on
        // CultureInfo.CurrentCulture flowing across awaits within one async
        // call chain. It doesn't: a probe against this exact TestServer setup
        // (PreserveExecutionContext at both its default and explicit true)
        // showed the handler always observing the host's own culture, never
        // the caller's — the ASP.NET request pipeline runs on infrastructure
        // that does not inherit the test method's ExecutionContext. So the
        // fix under test was a no-op either way and the test could not fail.
        //
        // Instead, invoke the handler directly via IMediator, resolved from
        // the factory's own DI container, from this method's own async flow —
        // CurrentCulture reliably flows across awaits there (see
        // https://learn.microsoft.com/dotnet/standard/globalization-localization/synchronizing-cultures).
        // Each Send gets its own DI scope (and so its own FileDbContext),
        // matching how two separate HTTP requests would each get a fresh
        // scope — but still against the real Postgres testcontainer.
        var originalCulture = CultureInfo.CurrentCulture;
        CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("tr-TR");
        try
        {
            // Precondition 1: the culture is genuinely active right here, not
            // just at the point it was assigned — a stray await or context
            // hop earlier in the chain could have already reset it.
            CultureInfo.CurrentCulture.Name.Should().Be("tr-TR",
                "the test proves nothing about the Turkish-culture bug unless the handler actually runs under tr-TR");

            // Precondition 2: the two names must genuinely fold differently
            // under tr-TR vs the invariant culture. If they didn't, a
            // passing test would prove nothing about culture-sensitivity at
            // all — this is the same divergence CreateFileCommandHandler's
            // ToLowerInvariant() fix targets.
            "FILE-TR.TXT".ToLower().Should().NotBe("FILE-TR.TXT".ToLowerInvariant(),
                "the test has no teeth unless Turkish case-folding of 'I' genuinely differs from the invariant fold");

            using (var firstScope = _factory.Services.CreateScope())
            {
                var mediator = firstScope.ServiceProvider.GetRequiredService<IMediator>();
                var first = await mediator.Send(new CreateFileCommand(
                    _factory.TestUserId, _factory.TestTenantId, null, "file-tr.txt", false, null, null, null, null));
                first.Name.Should().Be("file-tr.txt");
            }

            // Differs from "file-tr.txt" only by the case of "i" -> "I", the
            // exact letter Turkish folds differently from every other culture.
            using (var secondScope = _factory.Services.CreateScope())
            {
                var mediator = secondScope.ServiceProvider.GetRequiredService<IMediator>();
                Func<Task> secondCreate = () => mediator.Send(new CreateFileCommand(
                    _factory.TestUserId, _factory.TestTenantId, null, "FILE-TR.TXT", false, null, null, null, null));

                // The distinction under test: a clean ConflictException (-> 409
                // via ExceptionHandlingMiddleware) means the handler's own
                // duplicate check caught the collision under tr-TR. Any other
                // exception (e.g. DbUpdateException from the Postgres unique
                // index) means it fell through to a raw constraint violation
                // (-> 500) instead.
                await secondCreate.Should().ThrowAsync<ConflictException>(
                    "a case-only collision under Turkish culture must be rejected by the handler's own duplicate " +
                    "check (409 Conflict), not fall through to a raw database constraint violation (500)");
            }
        }
        finally
        {
            CultureInfo.CurrentCulture = originalCulture;
        }
    }

    [Fact]
    public async Task GetFile_WithoutAuth_Returns401()
    {
        var factory = new FileServiceFactory();
        await factory.InitializeAsync();
        try
        {
            var unauthClient = factory.CreateClient();
            var response = await unauthClient.GetAsync($"/api/v1/files/{Guid.NewGuid()}");
            response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        }
        finally
        {
            await ((IAsyncLifetime)factory).DisposeAsync();
            await factory.DisposeAsync();
        }
    }
}
