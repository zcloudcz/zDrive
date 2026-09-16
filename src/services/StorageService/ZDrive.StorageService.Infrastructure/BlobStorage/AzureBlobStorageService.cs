using System.Security.Cryptography;
using System.Text.Json;
using Azure.Storage;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;
using Microsoft.Extensions.Logging;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Domain.ValueObjects;

namespace ZDrive.StorageService.Infrastructure.BlobStorage;

public sealed class AzureBlobStorageService : IBlobStorageService
{
    private const string StorageContainer = "zdrive-storage";
    private const string SystemContainer = "zdrive-system";
    private static readonly TimeSpan SasExpiry = TimeSpan.FromHours(1);

    private readonly BlobServiceClient _blobServiceClient;
    private readonly StorageSharedKeyCredential? _sharedKeyCredential;
    private readonly ILogger<AzureBlobStorageService> _logger;

    public AzureBlobStorageService(
        BlobServiceClient blobServiceClient,
        StorageSharedKeyCredential? sharedKeyCredential,
        ILogger<AzureBlobStorageService> logger)
    {
        _blobServiceClient = blobServiceClient;
        _sharedKeyCredential = sharedKeyCredential;
        _logger = logger;
    }

    public string GenerateTempUploadSasUrl(Guid sessionId, int chunkIndex)
    {
        var blobPath = GetTempBlobPath(sessionId, chunkIndex);
        return GenerateSasUrl(SystemContainer, blobPath, BlobSasPermissions.Write | BlobSasPermissions.Create);
    }

    public async Task UploadChunkToTempAsync(Guid sessionId, int chunkIndex, Stream content, CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(SystemContainer);
        await containerClient.CreateIfNotExistsAsync(cancellationToken: ct);

        var blobPath = GetTempBlobPath(sessionId, chunkIndex);
        var blobClient = containerClient.GetBlobClient(blobPath);

        await blobClient.UploadAsync(content, overwrite: true, ct);
        _logger.LogDebug("Uploaded temp chunk {SessionId}/{ChunkIndex}", sessionId, chunkIndex);
    }

    public async Task<string> MoveChunkToFinalAsync(
        Guid sessionId, int chunkIndex, Guid tenantId, Guid userId, Guid fileId, string chunkHash, CancellationToken ct = default)
    {
        var systemContainer = _blobServiceClient.GetBlobContainerClient(SystemContainer);
        var storageContainer = _blobServiceClient.GetBlobContainerClient(StorageContainer);
        await storageContainer.CreateIfNotExistsAsync(cancellationToken: ct);

        var sourcePath = GetTempBlobPath(sessionId, chunkIndex);
        var destPath = GetFinalChunkPath(tenantId, userId, fileId, chunkHash);

        var sourceBlob = systemContainer.GetBlobClient(sourcePath);
        var destBlob = storageContainer.GetBlobClient(destPath);

        // Copy from temp to final
        var copyOperation = await destBlob.StartCopyFromUriAsync(sourceBlob.Uri, cancellationToken: ct);
        await copyOperation.WaitForCompletionAsync(ct);

        // Delete temp blob
        await sourceBlob.DeleteIfExistsAsync(cancellationToken: ct);

        _logger.LogDebug("Moved chunk {SessionId}/{ChunkIndex} to {DestPath}", sessionId, chunkIndex, destPath);
        return destPath;
    }

    public async Task UploadManifestAsync(Guid tenantId, Guid userId, Guid fileId, ChunkManifest manifest, CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(StorageContainer);
        await containerClient.CreateIfNotExistsAsync(cancellationToken: ct);

        var blobPath = GetManifestPath(tenantId, userId, fileId);
        var blobClient = containerClient.GetBlobClient(blobPath);

        var json = JsonSerializer.Serialize(manifest);
        using var stream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(json));
        await blobClient.UploadAsync(stream, overwrite: true, ct);

        _logger.LogDebug("Uploaded manifest for file {FileId}", fileId);
    }

    public async Task<ChunkManifest?> DownloadManifestAsync(Guid tenantId, Guid userId, Guid fileId, CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(StorageContainer);
        var blobPath = GetManifestPath(tenantId, userId, fileId);
        var blobClient = containerClient.GetBlobClient(blobPath);

        if (!await blobClient.ExistsAsync(ct))
            return null;

        var response = await blobClient.DownloadContentAsync(ct);
        return JsonSerializer.Deserialize<ChunkManifest>(response.Value.Content.ToString());
    }

    public async Task<ChunkManifest?> DownloadManifestSnapshotAsync(
        Guid tenantId, Guid userId, Guid fileId, string manifestHash, CancellationToken ct = default)
    {
        var container = _blobServiceClient.GetBlobContainerClient(StorageContainer);
        var blob = container.GetBlobClient(GetManifestSnapshotPath(tenantId, userId, fileId, manifestHash));
        if (!await blob.ExistsAsync(ct))
            return null;

        var response = await blob.DownloadContentAsync(ct);
        return JsonSerializer.Deserialize<ChunkManifest>(response.Value.Content.ToString());
    }

    public string GenerateDownloadSasUrl(Guid tenantId, Guid userId, Guid fileId)
    {
        var blobPath = GetManifestPath(tenantId, userId, fileId);
        return GenerateSasUrl(StorageContainer, blobPath, BlobSasPermissions.Read);
    }

    public string GenerateChunkDownloadSasUrl(Guid tenantId, Guid userId, Guid fileId, string chunkHash)
    {
        var blobPath = GetFinalChunkPath(tenantId, userId, fileId, chunkHash);
        return GenerateSasUrl(StorageContainer, blobPath, BlobSasPermissions.Read);
    }

    public async Task DeleteFileAsync(Guid tenantId, Guid userId, Guid fileId, CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(StorageContainer);
        var prefix = $"{tenantId}/{userId}/files/{fileId}/";

        await foreach (var blobItem in containerClient.GetBlobsAsync(prefix: prefix, cancellationToken: ct))
        {
            var blobClient = containerClient.GetBlobClient(blobItem.Name);
            await blobClient.DeleteIfExistsAsync(cancellationToken: ct);
        }

        _logger.LogInformation("Deleted all blobs for file {FileId}", fileId);
    }

    public async Task<string> ComputeTempChunkHashAsync(Guid sessionId, int chunkIndex, CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(SystemContainer);
        var blobClient = containerClient.GetBlobClient(GetTempBlobPath(sessionId, chunkIndex));

        // Stream the blob through the hash so large chunks never load into memory.
        await using var stream = await blobClient.OpenReadAsync(cancellationToken: ct);
        using var sha256 = SHA256.Create();
        var hash = await sha256.ComputeHashAsync(stream, ct);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    public async Task UploadManifestSnapshotAsync(
        Guid tenantId, Guid userId, Guid fileId, string manifestHash, ChunkManifest manifest, CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(StorageContainer);
        await containerClient.CreateIfNotExistsAsync(cancellationToken: ct);

        var blobClient = containerClient.GetBlobClient(GetManifestSnapshotPath(tenantId, userId, fileId, manifestHash));

        var json = JsonSerializer.Serialize(manifest);
        using var stream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(json));
        await blobClient.UploadAsync(stream, overwrite: true, ct);

        _logger.LogDebug("Uploaded manifest snapshot {ManifestHash} for file {FileId}", manifestHash, fileId);
    }

    public async Task<bool> RestoreManifestSnapshotAsync(
        Guid tenantId, Guid userId, Guid fileId, string manifestHash, CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(StorageContainer);
        var snapshotBlob = containerClient.GetBlobClient(GetManifestSnapshotPath(tenantId, userId, fileId, manifestHash));

        if (!await snapshotBlob.ExistsAsync(ct))
            return false;

        var currentBlob = containerClient.GetBlobClient(GetManifestPath(tenantId, userId, fileId));
        var copyOperation = await currentBlob.StartCopyFromUriAsync(snapshotBlob.Uri, cancellationToken: ct);
        await copyOperation.WaitForCompletionAsync(ct);

        _logger.LogInformation("Restored manifest snapshot {ManifestHash} for file {FileId}", manifestHash, fileId);
        return true;
    }

    public async Task<bool> TempChunkExistsAsync(Guid sessionId, int chunkIndex, CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(SystemContainer);
        var blobPath = GetTempBlobPath(sessionId, chunkIndex);
        var blobClient = containerClient.GetBlobClient(blobPath);
        return await blobClient.ExistsAsync(ct);
    }

    public async Task<long> GetTempChunkSizeAsync(Guid sessionId, int chunkIndex, CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(SystemContainer);
        var blobPath = GetTempBlobPath(sessionId, chunkIndex);
        var blobClient = containerClient.GetBlobClient(blobPath);
        var properties = await blobClient.GetPropertiesAsync(cancellationToken: ct);
        return properties.Value.ContentLength;
    }

    public async Task<Stream?> DownloadChunkAsync(Guid tenantId, Guid userId, Guid fileId, string chunkHash, CancellationToken ct = default)
    {
        var containerClient = _blobServiceClient.GetBlobContainerClient(StorageContainer);
        var blobClient = containerClient.GetBlobClient(GetFinalChunkPath(tenantId, userId, fileId, chunkHash));

        if (!await blobClient.ExistsAsync(ct))
            return null;

        return await blobClient.OpenReadAsync(cancellationToken: ct);
    }

    private string GenerateSasUrl(string containerName, string blobPath, BlobSasPermissions permissions)
    {
        if (_sharedKeyCredential is null)
        {
            // Fallback for environments without shared key (e.g., managed identity).
            // Return direct blob URL — caller must handle auth differently.
            var containerClient = _blobServiceClient.GetBlobContainerClient(containerName);
            return containerClient.GetBlobClient(blobPath).Uri.ToString();
        }

        var sasBuilder = new BlobSasBuilder
        {
            BlobContainerName = containerName,
            BlobName = blobPath,
            Resource = "b",
            ExpiresOn = DateTimeOffset.UtcNow.Add(SasExpiry)
        };
        sasBuilder.SetPermissions(permissions);

        var sasToken = sasBuilder.ToSasQueryParameters(_sharedKeyCredential).ToString();
        var blobUri = _blobServiceClient.GetBlobContainerClient(containerName).GetBlobClient(blobPath).Uri;
        return $"{blobUri}?{sasToken}";
    }

    private static string GetTempBlobPath(Guid sessionId, int chunkIndex) =>
        $"temp-uploads/{sessionId}/{chunkIndex}";

    private static string GetFinalChunkPath(Guid tenantId, Guid userId, Guid fileId, string chunkHash) =>
        $"{tenantId}/{userId}/files/{fileId}/chunks/{chunkHash}.blk";

    private static string GetManifestPath(Guid tenantId, Guid userId, Guid fileId) =>
        $"{tenantId}/{userId}/files/{fileId}/manifest.json";

    private static string GetManifestSnapshotPath(Guid tenantId, Guid userId, Guid fileId, string manifestHash) =>
        $"{tenantId}/{userId}/files/{fileId}/manifests/{manifestHash}.json";
}
