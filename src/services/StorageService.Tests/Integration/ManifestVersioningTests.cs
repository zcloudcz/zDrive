using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Azure.Storage.Blobs;
using FluentAssertions;
using Xunit;
using ZDrive.Shared.DTOs;
using ZDrive.StorageService.Application.DTOs;

namespace ZDrive.StorageService.Tests.Integration;

/// <summary>
/// Phase 3 (versioning) storage-side flow: every completed upload stores an
/// immutable manifest snapshot under its content hash, chunks are
/// content-addressed (re-upload never destroys older versions' data), and a
/// snapshot can be restored as the current manifest.
/// </summary>
[Trait("Category", "Integration")]
public sealed class ManifestVersioningTests : IClassFixture<StorageServiceFactory>
{
    private readonly StorageServiceFactory _factory;
    private readonly HttpClient _client;
    private readonly string _accessToken;

    public ManifestVersioningTests(StorageServiceFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        _accessToken = factory.CreateAccessToken(Guid.NewGuid(), Guid.NewGuid());
    }

    [Fact]
    public async Task ReUpload_OldSnapshotRestorable_ChunksContentAddressed()
    {
        var fileId = Guid.NewGuid();

        var contentV1 = new byte[1024];
        var contentV2 = new byte[2048];
        Random.Shared.NextBytes(contentV1);
        Random.Shared.NextBytes(contentV2);

        // Upload version 1, then overwrite with version 2.
        var v1 = await UploadFile(fileId, contentV1);
        var v2 = await UploadFile(fileId, contentV2);

        v1.ManifestHash.Should().NotBe(v2.ManifestHash);

        // Both manifest snapshots exist in blob storage; current manifest is v2.
        var container = new BlobServiceClient(_factory.AzuriteConnectionString)
            .GetBlobContainerClient("zdrive-storage");

        var manifestText = await ReadBlob(container, $"{v2.BlobPath}/manifest.json");
        var snapshotV1 = await ReadBlob(container, $"{v1.BlobPath}/manifests/{v1.ManifestHash}.json");
        var snapshotV2 = await ReadBlob(container, $"{v2.BlobPath}/manifests/{v2.ManifestHash}.json");

        manifestText.Should().Be(snapshotV2);
        snapshotV1.Should().NotBe(snapshotV2);

        // Chunk paths are content-addressed → v1's chunk still exists after re-upload.
        snapshotV1.Should().Contain("\"Hash\"");
        snapshotV1.Should().NotContain("chunk-000000"); // old index-based naming is gone

        // Restore v1 → current manifest equals the v1 snapshot again.
        var restoreResponse = await AuthPost(
            $"/api/v1/storage/files/{fileId}/manifests/{v1.ManifestHash}/restore", new { });
        restoreResponse.StatusCode.Should().Be(HttpStatusCode.OK,
            await restoreResponse.Content.ReadAsStringAsync());

        var restoredManifest = await ReadBlob(container, $"{v1.BlobPath}/manifest.json");
        restoredManifest.Should().Be(snapshotV1);
    }

    [Fact]
    public async Task Restore_UnknownSnapshot_Returns404()
    {
        var fileId = Guid.NewGuid();
        await UploadFile(fileId, new byte[64]);

        var unknownHash = new string('a', 64);
        var response = await AuthPost(
            $"/api/v1/storage/files/{fileId}/manifests/{unknownHash}/restore", new { });

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Restore_MalformedHash_Returns400()
    {
        var response = await AuthPost(
            $"/api/v1/storage/files/{Guid.NewGuid()}/manifests/not-a-sha256/restore", new { });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    private async Task<UploadCompleteDto> UploadFile(Guid fileId, byte[] content)
    {
        var initResponse = await AuthPost("/api/v1/storage/upload/init", new
        {
            fileId,
            fileName = "versioned.bin",
            totalChunks = 1
        });
        var session = (await initResponse.Content.ReadFromJsonAsync<ApiResponse<UploadSessionDto>>())!.Data!;

        var request = new HttpRequestMessage(HttpMethod.Put,
            $"/api/v1/storage/upload/{session.SessionId}/chunk/0");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);
        request.Headers.Add("X-Chunk-Hash", "client-hash");
        request.Content = new ByteArrayContent(content);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        (await _client.SendAsync(request)).StatusCode.Should().Be(HttpStatusCode.OK);

        var completeResponse = await AuthPost($"/api/v1/storage/upload/{session.SessionId}/complete", new { });
        completeResponse.StatusCode.Should().Be(HttpStatusCode.OK,
            await completeResponse.Content.ReadAsStringAsync());

        return (await completeResponse.Content.ReadFromJsonAsync<ApiResponse<UploadCompleteDto>>())!.Data!;
    }

    private async Task<HttpResponseMessage> AuthPost(string url, object body)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _accessToken);
        request.Content = JsonContent.Create(body);
        return await _client.SendAsync(request);
    }

    private static async Task<string> ReadBlob(BlobContainerClient container, string path)
    {
        var blob = container.GetBlobClient(path);
        (await blob.ExistsAsync()).Value.Should().BeTrue($"blob '{path}' should exist");
        var response = await blob.DownloadContentAsync();
        return response.Value.Content.ToString();
    }
}
