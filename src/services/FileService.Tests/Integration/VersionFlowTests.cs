using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using FluentAssertions;
using Xunit;
using ZDrive.FileService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Tests.Integration;

/// <summary>
/// Phase 3 (versioning) metadata flow: record versions after uploads, list
/// them, restore an older version, and prune history beyond the retention
/// limit (factory configures MaxVersionsPerFile = 3).
/// </summary>
[Trait("Category", "Integration")]
public sealed class VersionFlowTests : IClassFixture<FileServiceFactory>
{
    private readonly FileServiceFactory _factory;
    private readonly HttpClient _client;

    public VersionFlowTests(FileServiceFactory factory)
    {
        _factory = factory;
        _client = factory.CreateAuthenticatedClient();
    }

    [Fact]
    public async Task CreateVersions_ListOrderedDescending_FileMetadataUpdated()
    {
        var file = await CreateFile("versioned-file.txt");

        var v1 = await CreateVersion(file.Id, FakeManifestHash("a"), sizeBytes: 100, comment: "first");
        var v2 = await CreateVersion(file.Id, FakeManifestHash("b"), sizeBytes: 200, comment: "second");

        v1.VersionNumber.Should().Be(1);
        v2.VersionNumber.Should().Be(2);

        var versions = await ListVersions(file.Id);
        versions.Should().HaveCount(2);
        versions[0].VersionNumber.Should().Be(2);
        versions[0].Comment.Should().Be("second");
        versions[1].VersionNumber.Should().Be(1);

        // The file's metadata follows the latest version.
        var updated = await GetFile(file.Id);
        updated.SizeBytes.Should().Be(200);
    }

    [Fact]
    public async Task RestoreVersion_AppendsNewVersion_RollsBackFileMetadata()
    {
        var file = await CreateFile("restore-me.txt");

        var v1 = await CreateVersion(file.Id, FakeManifestHash("c"), sizeBytes: 111);
        await CreateVersion(file.Id, FakeManifestHash("d"), sizeBytes: 222);

        var restoreResponse = await _client.PostAsync(
            $"/api/v1/files/{file.Id}/versions/{v1.Id}/restore", null);
        restoreResponse.StatusCode.Should().Be(HttpStatusCode.OK,
            await restoreResponse.Content.ReadAsStringAsync());

        var restored = (await restoreResponse.Content.ReadFromJsonAsync<ApiResponse<FileVersionDto>>())!.Data!;

        // Restore is recorded as a NEW version pointing at v1's content.
        restored.VersionNumber.Should().Be(3);
        restored.BlobVersionId.Should().Be(v1.BlobVersionId);
        restored.SizeBytes.Should().Be(111);
        restored.Comment.Should().Be("Restored from version 1");

        var updated = await GetFile(file.Id);
        updated.SizeBytes.Should().Be(111);
    }

    [Fact]
    public async Task Retention_KeepsOnlyNewestVersions()
    {
        var file = await CreateFile("retained.txt");

        for (var i = 1; i <= 5; i++)
            await CreateVersion(file.Id, FakeManifestHash($"v{i}"), sizeBytes: i * 10);

        var versions = await ListVersions(file.Id);

        versions.Should().HaveCount(FileServiceFactory.MaxVersionsPerFile);
        versions.Select(v => v.VersionNumber).Should().BeEquivalentTo([5, 4, 3]);
    }

    [Fact]
    public async Task RestoreVersion_UnknownVersion_Returns404()
    {
        var file = await CreateFile("no-versions.txt");

        var response = await _client.PostAsync(
            $"/api/v1/files/{file.Id}/versions/{Guid.NewGuid()}/restore", null);

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task CreateVersion_ForeignUsersFile_Returns404()
    {
        var file = await CreateFile("not-yours.txt");

        var strangerClient = _factory.CreateAuthenticatedClient(Guid.NewGuid(), Guid.NewGuid());
        var response = await strangerClient.PostAsJsonAsync($"/api/v1/files/{file.Id}/versions", new
        {
            blobVersionId = FakeManifestHash("z"),
            sizeBytes = 10L
        });

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GetVersions_NonExistentFile_Returns404()
    {
        var response = await _client.GetAsync($"/api/v1/files/{Guid.NewGuid()}/versions");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    private async Task<FileDto> CreateFile(string name)
    {
        var response = await _client.PostAsJsonAsync("/api/v1/files", new
        {
            name,
            isFolder = false,
            sizeBytes = 0L,
            mimeType = "text/plain"
        });
        response.StatusCode.Should().Be(HttpStatusCode.Created,
            await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
    }

    private async Task<FileVersionDto> CreateVersion(
        Guid fileId, string blobVersionId, long sizeBytes, string? comment = null)
    {
        var response = await _client.PostAsJsonAsync($"/api/v1/files/{fileId}/versions", new
        {
            blobVersionId,
            sizeBytes,
            manifestHash = blobVersionId,
            comment
        });
        response.StatusCode.Should().Be(HttpStatusCode.OK,
            await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<ApiResponse<FileVersionDto>>())!.Data!;
    }

    private async Task<List<FileVersionDto>> ListVersions(Guid fileId)
    {
        var response = await _client.GetAsync($"/api/v1/files/{fileId}/versions");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        return (await response.Content.ReadFromJsonAsync<ApiResponse<List<FileVersionDto>>>())!.Data!;
    }

    private async Task<FileDto> GetFile(Guid fileId)
    {
        var response = await _client.GetAsync($"/api/v1/files/{fileId}");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        return (await response.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
    }

    /// <summary>Deterministic valid SHA-256 hex string derived from a seed.</summary>
    private static string FakeManifestHash(string seed) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(seed))).ToLowerInvariant();
}
