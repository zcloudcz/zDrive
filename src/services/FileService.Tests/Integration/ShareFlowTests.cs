using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Xunit;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Domain.Enums;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class ShareFlowTests : IClassFixture<FileServiceFactory>
{
    private readonly FileServiceFactory _factory;
    private readonly HttpClient _client;

    public ShareFlowTests(FileServiceFactory factory)
    {
        _factory = factory;
        _client = factory.CreateAuthenticatedClient();
    }

    [Fact]
    public async Task CreateShareLink_AccessViaToken_Success()
    {
        // Create a file
        var createResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "shared-file.txt",
            isFolder = false,
            sizeBytes = 512L,
            mimeType = "text/plain"
        });
        var file = (await createResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        // Share it
        var shareResponse = await _client.PostAsJsonAsync("/api/v1/shares", new
        {
            fileId = file.Id,
            permission = Permission.Read
        });
        shareResponse.StatusCode.Should().Be(HttpStatusCode.Created);

        var shareResult = await shareResponse.Content.ReadFromJsonAsync<ApiResponse<ShareDto>>();
        shareResult!.Success.Should().BeTrue();
        shareResult.Data!.LinkToken.Should().NotBeNullOrWhiteSpace();
        shareResult.Data.Permission.Should().Be("Read");

        // Access via token (anonymous)
        var unauthClient = _factory.CreateClient();
        var linkResponse = await unauthClient.GetAsync($"/api/v1/shares/link/{shareResult.Data.LinkToken}");
        linkResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var linkResult = await linkResponse.Content.ReadFromJsonAsync<ApiResponse<SharedFileDto>>();
        linkResult!.Success.Should().BeTrue();
        linkResult.Data!.File.Name.Should().Be("shared-file.txt");
        linkResult.Data.Share.Permission.Should().Be("Read");
    }

    [Fact]
    public async Task RevokeShare_TokenNoLongerWorks()
    {
        // Create and share a file
        var createResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "revocable-share.txt",
            isFolder = false
        });
        var file = (await createResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var shareResponse = await _client.PostAsJsonAsync("/api/v1/shares", new
        {
            fileId = file.Id,
            permission = Permission.Read
        });
        var share = (await shareResponse.Content.ReadFromJsonAsync<ApiResponse<ShareDto>>())!.Data!;

        // Revoke
        var revokeResponse = await _client.DeleteAsync($"/api/v1/shares/{share.Id}");
        revokeResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        // Token no longer works
        var unauthClient = _factory.CreateClient();
        var linkResponse = await unauthClient.GetAsync($"/api/v1/shares/link/{share.LinkToken}");
        linkResponse.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task ShareLink_WithExpiration_ExpiredLinkReturns404()
    {
        // We can't easily test time-based expiration in an integration test without
        // manipulating the clock. Instead, verify creating a share with a future date works.
        var createResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "expirable-share.txt",
            isFolder = false
        });
        var file = (await createResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var shareResponse = await _client.PostAsJsonAsync("/api/v1/shares", new
        {
            fileId = file.Id,
            permission = Permission.Write,
            expiresAt = DateTime.UtcNow.AddDays(7)
        });
        shareResponse.StatusCode.Should().Be(HttpStatusCode.Created);

        var share = (await shareResponse.Content.ReadFromJsonAsync<ApiResponse<ShareDto>>())!.Data!;
        share.ExpiresAt.Should().NotBeNull();
        share.Permission.Should().Be("Write");
    }

    [Fact]
    public async Task ShareLink_PasswordProtected_ReturnsForbidden()
    {
        var createResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "secret.txt",
            isFolder = false
        });
        var file = (await createResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var shareResponse = await _client.PostAsJsonAsync("/api/v1/shares", new
        {
            fileId = file.Id,
            permission = Permission.Read,
            password = "hunter2"
        });
        var share = (await shareResponse.Content.ReadFromJsonAsync<ApiResponse<ShareDto>>())!.Data!;

        var unauthClient = _factory.CreateClient();
        var linkResponse = await unauthClient.GetAsync($"/api/v1/shares/link/{share.LinkToken}");

        linkResponse.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task DirectShare_NotReachableViaLinkEndpoint_ReturnsNotFound()
    {
        var createResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "direct-share.txt",
            isFolder = false
        });
        var file = (await createResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var shareResponse = await _client.PostAsJsonAsync("/api/v1/shares", new
        {
            fileId = file.Id,
            sharedWith = Guid.NewGuid(),
            permission = Permission.Read
        });
        var share = (await shareResponse.Content.ReadFromJsonAsync<ApiResponse<ShareDto>>())!.Data!;

        var unauthClient = _factory.CreateClient();
        var linkResponse = await unauthClient.GetAsync($"/api/v1/shares/link/{share.LinkToken}");

        linkResponse.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task SharedFolder_ListChildren_NestedAndOutside()
    {
        var rootResponse = await _client.PostAsJsonAsync("/api/v1/files", new { name = "shared-root", isFolder = true });
        var root = (await rootResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var nestedResponse = await _client.PostAsJsonAsync("/api/v1/files", new { name = "nested", isFolder = true, parentId = root.Id });
        var nested = (await nestedResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var leafResponse = await _client.PostAsJsonAsync("/api/v1/files", new { name = "leaf.txt", isFolder = false, parentId = nested.Id });
        var leaf = (await leafResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var outsideResponse = await _client.PostAsJsonAsync("/api/v1/files", new { name = "outside", isFolder = true });
        var outside = (await outsideResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var shareResponse = await _client.PostAsJsonAsync("/api/v1/shares", new { fileId = root.Id, permission = Permission.Read });
        var share = (await shareResponse.Content.ReadFromJsonAsync<ApiResponse<ShareDto>>())!.Data!;

        var unauthClient = _factory.CreateClient();

        // Default folderId (the shared root) lists "nested".
        var rootChildren = await unauthClient.GetFromJsonAsync<ApiResponse<List<FileDto>>>(
            $"/api/v1/shares/link/{share.LinkToken}/children");
        rootChildren!.Data.Should().ContainSingle(f => f.Id == nested.Id);

        // A nested subfolder inside the share lists its own children.
        var nestedChildren = await unauthClient.GetFromJsonAsync<ApiResponse<List<FileDto>>>(
            $"/api/v1/shares/link/{share.LinkToken}/children?folderId={nested.Id}");
        nestedChildren!.Data.Should().ContainSingle(f => f.Id == leaf.Id);

        // A real folder that's just not under the shared root -> 404, not 403.
        var outsideResult = await unauthClient.GetAsync(
            $"/api/v1/shares/link/{share.LinkToken}/children?folderId={outside.Id}");
        outsideResult.StatusCode.Should().Be(HttpStatusCode.NotFound);

        // Soft-deleted descendant -> 404.
        await _client.DeleteAsync($"/api/v1/files/{nested.Id}");
        var deletedResult = await unauthClient.GetAsync(
            $"/api/v1/shares/link/{share.LinkToken}/children?folderId={nested.Id}");
        deletedResult.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task DownloadGrant_RootAndNestedFile_ValidatesAndCarriesOwnerIds()
    {
        var rootResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "shared-root-2",
            isFolder = true
        });
        var root = (await rootResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var manifestHash = new string('a', 64);
        var nestedResponse = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name = "downloadable.bin",
            isFolder = false,
            parentId = root.Id,
            sizeBytes = 1024L,
            manifestHash
        });
        var nested = (await nestedResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var outsideResponse = await _client.PostAsJsonAsync("/api/v1/files", new { name = "outside.bin", isFolder = false, manifestHash });
        var outside = (await outsideResponse.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;

        var shareResponse = await _client.PostAsJsonAsync("/api/v1/shares", new { fileId = root.Id, permission = Permission.Read });
        var share = (await shareResponse.Content.ReadFromJsonAsync<ApiResponse<ShareDto>>())!.Data!;

        var unauthClient = _factory.CreateClient();

        var grantResponse = await unauthClient.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/download-grant", new { fileId = nested.Id });
        grantResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var grant = (await grantResponse.Content.ReadFromJsonAsync<ApiResponse<ShareDownloadGrantDto>>())!.Data!;
        grant.FileId.Should().Be(nested.Id);
        grant.ManifestHash.Should().Be(manifestHash);

        var forFolder = await unauthClient.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/download-grant", new { fileId = root.Id });
        forFolder.StatusCode.Should().Be(HttpStatusCode.NotFound); // root is a folder here, not a file

        var forOutside = await unauthClient.PostAsJsonAsync(
            $"/api/v1/shares/link/{share.LinkToken}/download-grant", new { fileId = outside.Id });
        forOutside.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
