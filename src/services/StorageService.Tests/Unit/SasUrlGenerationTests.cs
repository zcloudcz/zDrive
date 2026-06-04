using Azure.Storage;
using Azure.Storage.Blobs;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZDrive.StorageService.Infrastructure.BlobStorage;

namespace ZDrive.StorageService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class SasUrlGenerationTests
{
    private readonly AzureBlobStorageService _service;

    public SasUrlGenerationTests()
    {
        // Use Azurite well-known credentials
        var connectionString = "UseDevelopmentStorage=true";
        var blobServiceClient = new BlobServiceClient(connectionString);
        var sharedKeyCredential = new StorageSharedKeyCredential(
            "devstoreaccount1",
            "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==");

        _service = new AzureBlobStorageService(
            blobServiceClient,
            sharedKeyCredential,
            NullLogger<AzureBlobStorageService>.Instance);
    }

    [Fact]
    public void GenerateTempUploadSasUrl_ContainsSessionAndChunk()
    {
        var sessionId = Guid.NewGuid();
        var url = _service.GenerateTempUploadSasUrl(sessionId, 5);

        url.Should().Contain("zdrive-system");
        url.Should().Contain($"temp-uploads/{sessionId}/5");
        url.Should().Contain("sig="); // SAS signature present
    }

    [Fact]
    public void GenerateDownloadSasUrl_ContainsTenantUserFile()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var fileId = Guid.NewGuid();

        var url = _service.GenerateDownloadSasUrl(tenantId, userId, fileId);

        url.Should().Contain("zdrive-storage");
        url.Should().Contain($"{tenantId}/{userId}/files/{fileId}/manifest.json");
        url.Should().Contain("sig=");
    }

    [Fact]
    public void GenerateChunkDownloadSasUrl_ContainsChunkHash()
    {
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var fileId = Guid.NewGuid();
        var chunkHash = "abc123def456";

        var url = _service.GenerateChunkDownloadSasUrl(tenantId, userId, fileId, chunkHash);

        url.Should().Contain("zdrive-storage");
        url.Should().Contain($"chunks/{chunkHash}.blk");
        url.Should().Contain("sig=");
    }
}
