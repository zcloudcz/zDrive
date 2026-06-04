using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Xunit;
using ZDrive.FileService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class FileFlowTests : IClassFixture<FileServiceFactory>
{
    private readonly HttpClient _client;

    public FileFlowTests(FileServiceFactory factory)
    {
        _client = factory.CreateAuthenticatedClient();
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
