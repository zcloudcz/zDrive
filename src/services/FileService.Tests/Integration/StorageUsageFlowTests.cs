using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Xunit;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Tests.Integration;

/// <summary>
/// Package B (per-user storage quota) against real Postgres/Npgsql — the
/// unit tests exercise the same logic against EF Core InMemory, which does
/// not prove the aggregate SUM actually translates to SQL.
///
/// The small quota needed to make a couple of versions reach a limit is NOT
/// applied to the shared FileServiceFactory (that would leak a 1000-byte
/// quota into every other FileService integration test, which record much
/// bigger totals across the suite and would then be wrongly refused with
/// 413). Instead each test derives its own host via WithWebHostBuilder,
/// which only overrides Storage:DefaultUserQuotaBytes for that host, and
/// authenticates as its own fresh user so no other test's writes can count
/// into "used".
/// </summary>
[Trait("Category", "Integration")]
public sealed class StorageUsageFlowTests : IClassFixture<FileServiceFactory>
{
    private const long QuotaBytes = 1000;

    private readonly FileServiceFactory _factory;

    public StorageUsageFlowTests(FileServiceFactory factory) => _factory = factory;

    private HttpClient CreateQuotaClient()
    {
        var host = _factory.WithWebHostBuilder(builder =>
            builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(
            [
                new KeyValuePair<string, string?>("Storage:DefaultUserQuotaBytes", QuotaBytes.ToString())
            ])));

        var client = host.CreateClient();
        var userId = Guid.NewGuid();
        var tenantId = Guid.NewGuid();
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", _factory.CreateTestToken(userId, tenantId));
        return client;
    }

    [Fact]
    public async Task GetUsage_TrashedNodeAndOldVersion_SumsAllOfIt()
    {
        var client = CreateQuotaClient();

        // File A: two versions (300 + 200). The first is "old" once the
        // second is recorded, but both still sit in blob storage.
        // used: 0 -> 300 -> 500.
        var fileA = await CreateFile(client, "a.txt");
        await CreateVersion(client, fileA.Id, sizeBytes: 300);
        await CreateVersion(client, fileA.Id, sizeBytes: 200);

        // File B: one version (400), then trashed — soft delete keeps the
        // version row (see CLAUDE.md: used bytes counts trashed nodes too).
        // used: 500 -> 900 (trashing does not change it).
        var fileB = await CreateFile(client, "b.txt");
        await CreateVersion(client, fileB.Id, sizeBytes: 400);
        var deleteResponse = await client.DeleteAsync($"/api/v1/files/{fileB.Id}");
        deleteResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        // Neither file reached FileServiceFactory.MaxVersionsPerFile (3), so
        // nothing was pruned — the SUM is a plain 300 + 200 + 400 = 900.
        var usage = await GetUsage(client);

        usage.LimitBytes.Should().Be(QuotaBytes);
        usage.UsedBytes.Should().Be(900);
    }

    [Fact]
    public async Task CreateVersion_PushingUsageOverLimit_Returns413QuotaExceeded()
    {
        var client = CreateQuotaClient();

        // used: 0 -> 900 (well under the 1000-byte limit — must succeed).
        var file = await CreateFile(client, "big.txt");
        await CreateVersion(client, file.Id, sizeBytes: 900);

        // used would become 900 + 200 = 1100 > 1000 — the only step expected
        // to be refused.
        var response = await client.PostAsJsonAsync($"/api/v1/files/{file.Id}/versions", new
        {
            blobVersionId = FakeManifestHash("over-limit"),
            sizeBytes = 200L,
            manifestHash = FakeManifestHash("over-limit")
        });

        response.StatusCode.Should().Be((HttpStatusCode)413);
        var body = await response.Content.ReadFromJsonAsync<ApiResponse<object>>();
        body!.Error!.Code.Should().Be("QUOTA_EXCEEDED");
    }

    private static async Task<FileDto> CreateFile(HttpClient client, string name)
    {
        var response = await client.PostAsJsonAsync("/api/v1/files", new
        {
            name,
            isFolder = false,
            sizeBytes = 0L,
            mimeType = "text/plain"
        });
        response.StatusCode.Should().Be(HttpStatusCode.Created, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<ApiResponse<FileDto>>())!.Data!;
    }

    private static async Task<FileVersionDto> CreateVersion(HttpClient client, Guid fileId, long sizeBytes)
    {
        var hash = FakeManifestHash($"{fileId}-{sizeBytes}");
        var response = await client.PostAsJsonAsync($"/api/v1/files/{fileId}/versions", new
        {
            blobVersionId = hash,
            sizeBytes,
            manifestHash = hash
        });
        response.StatusCode.Should().Be(HttpStatusCode.OK, await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<ApiResponse<FileVersionDto>>())!.Data!;
    }

    private static async Task<StorageUsage> GetUsage(HttpClient client)
    {
        var response = await client.GetAsync("/api/v1/files/usage");
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        return (await response.Content.ReadFromJsonAsync<ApiResponse<StorageUsage>>())!.Data!;
    }

    private static string FakeManifestHash(string seed) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(seed))).ToLowerInvariant();
}
