using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using FluentAssertions;
using Xunit;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Tests.Integration;

/// <summary>
/// Package B (per-user storage quota) against real Postgres/Npgsql — the
/// unit tests exercise the same logic against EF Core InMemory, which does
/// not prove the aggregate SUM actually translates to SQL. FileServiceFactory
/// overrides Storage:DefaultUserQuotaBytes down to
/// <see cref="FileServiceFactory.DefaultUserQuotaBytes"/> so a couple of
/// small versions are enough to reach the limit.
/// </summary>
[Trait("Category", "Integration")]
public sealed class StorageUsageFlowTests : IClassFixture<FileServiceFactory>
{
    private readonly FileServiceFactory _factory;
    private readonly HttpClient _client;

    public StorageUsageFlowTests(FileServiceFactory factory)
    {
        _factory = factory;
        _client = factory.CreateAuthenticatedClient();
    }

    [Fact]
    public async Task GetUsage_TrashedNodeAndOldVersion_SumsAllOfIt()
    {
        // File A: two versions (300 + 200) — the first is "old" once the
        // second is recorded, but both still sit in blob storage.
        var fileA = await CreateFile("a.txt");
        await CreateVersion(fileA.Id, sizeBytes: 300);
        await CreateVersion(fileA.Id, sizeBytes: 200);

        // File B: one version (400), then trashed — soft delete keeps the
        // version rows (see CLAUDE.md: used bytes counts trashed nodes too).
        var fileB = await CreateFile("b.txt");
        await CreateVersion(fileB.Id, sizeBytes: 400);
        var deleteResponse = await _client.DeleteAsync($"/api/v1/files/{fileB.Id}");
        deleteResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var usage = await GetUsage();

        usage.LimitBytes.Should().Be(FileServiceFactory.DefaultUserQuotaBytes);
        usage.UsedBytes.Should().Be(300 + 200 + 400);
    }

    [Fact]
    public async Task CreateVersion_PushingUsageOverLimit_Returns413QuotaExceeded()
    {
        var file = await CreateFile("big.txt");
        await CreateVersion(file.Id, sizeBytes: 900);

        // Usage is already 900 of the 1000-byte limit; 200 more pushes past it.
        var response = await _client.PostAsJsonAsync($"/api/v1/files/{file.Id}/versions", new
        {
            blobVersionId = FakeManifestHash("over-limit"),
            sizeBytes = 200L,
            manifestHash = FakeManifestHash("over-limit")
        });

        response.StatusCode.Should().Be((HttpStatusCode)413);
        var body = await response.Content.ReadFromJsonAsync<ApiResponse<object>>();
        body!.Error!.Code.Should().Be("QUOTA_EXCEEDED");
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
        response.StatusCode.Should().Be(HttpStatusCode.Created, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
    }

    private async Task<FileVersionDto> CreateVersion(Guid fileId, long sizeBytes)
    {
        var hash = FakeManifestHash($"{fileId}-{sizeBytes}");
        var response = await _client.PostAsJsonAsync($"/api/v1/files/{fileId}/versions", new
        {
            blobVersionId = hash,
            sizeBytes,
            manifestHash = hash
        });
        response.StatusCode.Should().Be(HttpStatusCode.OK, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<ApiResponse<FileVersionDto>>())!.Data!;
    }

    private async Task<StorageUsage> GetUsage()
    {
        var response = await _client.GetAsync("/api/v1/files/usage");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        return (await response.Content.ReadFromJsonAsync<ApiResponse<StorageUsage>>())!.Data!;
    }

    private static string FakeManifestHash(string seed) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(seed))).ToLowerInvariant();
}
