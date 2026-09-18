using ZDrive.StorageService.Domain.ValueObjects;

namespace ZDrive.StorageService.Application.Interfaces;

public interface IBlobStorageService
{
    /// <summary>
    /// Generates a SAS URL for uploading a chunk to temp storage.
    /// </summary>
    string GenerateTempUploadSasUrl(Guid sessionId, int chunkIndex);

    /// <summary>
    /// Uploads a chunk stream to temporary storage.
    /// </summary>
    Task UploadChunkToTempAsync(Guid sessionId, int chunkIndex, Stream content, CancellationToken ct = default);

    /// <summary>
    /// Moves a chunk from temp storage to final blob path.
    /// </summary>
    Task<string> MoveChunkToFinalAsync(Guid sessionId, int chunkIndex, Guid tenantId, Guid userId, Guid fileId, string chunkHash, CancellationToken ct = default);

    /// <summary>
    /// Uploads a manifest JSON for a completed file.
    /// </summary>
    Task UploadManifestAsync(Guid tenantId, Guid userId, Guid fileId, ChunkManifest manifest, CancellationToken ct = default);

    /// <summary>
    /// Downloads a manifest JSON for a file.
    /// </summary>
    Task<ChunkManifest?> DownloadManifestAsync(Guid tenantId, Guid userId, Guid fileId, CancellationToken ct = default);

    Task<ChunkManifest?> DownloadManifestSnapshotAsync(Guid tenantId, Guid userId, Guid fileId, string manifestHash, CancellationToken ct = default);

    /// <summary>
    /// Generates a SAS URL for downloading the complete file (manifest path).
    /// </summary>
    string GenerateDownloadSasUrl(Guid tenantId, Guid userId, Guid fileId);

    /// <summary>
    /// Generates a SAS URL for downloading a specific chunk.
    /// </summary>
    string GenerateChunkDownloadSasUrl(Guid tenantId, Guid userId, Guid fileId, string chunkHash);

    Task DeleteTempUploadAsync(Guid sessionId, CancellationToken ct = default);

    /// <summary>
    /// Deletes a single temp chunk (not the whole session) — used when a
    /// chunk turns out to push a capped upload session over its maxBytes:
    /// the bytes were already written (streamed uploads have no reliable
    /// upfront size, e.g. chunked transfer-encoding has no Content-Length),
    /// so the cap is enforced by measuring what actually landed and removing
    /// it if it doesn't fit, rather than by trusting a client-supplied size.
    /// </summary>
    Task DeleteTempChunkAsync(Guid sessionId, int chunkIndex, CancellationToken ct = default);

    /// <summary>
    /// Deletes all blobs (chunks + manifest) for a file.
    /// </summary>
    Task DeleteFileAsync(Guid tenantId, Guid userId, Guid fileId, CancellationToken ct = default);

    /// <summary>
    /// Computes the SHA-256 hash (lowercase hex) of a temp chunk's content.
    /// Used as the content address of the final chunk blob, so identical
    /// content is stored once and older file versions keep their chunks.
    /// </summary>
    Task<string> ComputeTempChunkHashAsync(Guid sessionId, int chunkIndex, CancellationToken ct = default);

    /// <summary>
    /// Stores an immutable snapshot of a manifest under its content hash.
    /// One snapshot per file version; the latest manifest stays at manifest.json.
    /// </summary>
    Task UploadManifestSnapshotAsync(Guid tenantId, Guid userId, Guid fileId, string manifestHash, ChunkManifest manifest, CancellationToken ct = default);

    /// <summary>
    /// Makes a manifest snapshot the current manifest (manifest.json).
    /// Returns false when the snapshot does not exist.
    /// </summary>
    Task<bool> RestoreManifestSnapshotAsync(Guid tenantId, Guid userId, Guid fileId, string manifestHash, CancellationToken ct = default);

    /// <summary>
    /// Checks if a temp chunk exists.
    /// </summary>
    Task<bool> TempChunkExistsAsync(Guid sessionId, int chunkIndex, CancellationToken ct = default);

    /// <summary>
    /// Gets the size of a temp chunk in bytes.
    /// </summary>
    Task<long> GetTempChunkSizeAsync(Guid sessionId, int chunkIndex, CancellationToken ct = default);

    /// <summary>
    /// Opens a read stream for a final chunk's content, so the API can proxy
    /// the bytes to clients that cannot fetch a SAS URL directly (web has no
    /// blob CORS configured). Null when the chunk does not exist.
    /// </summary>
    Task<Stream?> DownloadChunkAsync(Guid tenantId, Guid userId, Guid fileId, string chunkHash, CancellationToken ct = default);
}
