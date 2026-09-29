using System.Security.Cryptography;
using MediatR;
using ZDrive.PhotoService.Application.Interfaces.Ingest;
using ZDrive.Shared.Exceptions;
using ZDrive.StorageService.Application.Commands.PutThumbnail;
using ZDrive.StorageService.Application.Queries.DownloadChunk;
using ZDrive.StorageService.Application.Queries.GetManifest;
using ZDrive.StorageService.Application.Queries.GetThumbnail;

namespace ZDrive.Api.Photos;

/// <summary>
/// Photo → Storage boundary: originals are read through the same manifest and
/// chunk queries the download endpoints use, thumbnails are written and read
/// through the thumbnail command/query.
/// </summary>
public sealed class StorageServicePhotoAccess : IPhotoSourceReader, IThumbnailStore
{
    private readonly IMediator _mediator;

    public StorageServicePhotoAccess(IMediator mediator) => _mediator = mediator;

    public async Task<byte[]> ReadAsync(
        Guid tenantId, Guid userId, Guid fileId, string manifestHash, long maxBytes, CancellationToken cancellationToken)
    {
        try
        {
            // The snapshot is immutable and content-addressed, so it cannot be
            // half-updated by a concurrent version restore.
            var manifest = await _mediator.Send(new GetManifestQuery(tenantId, userId, fileId, manifestHash), cancellationToken);
            if (manifest.TotalSize > maxBytes)
                throw new PermanentPhotoException($"File is {manifest.TotalSize} bytes, above the {maxBytes} byte limit.");

            var result = new MemoryStream(checked((int)manifest.TotalSize));
            foreach (var chunk in manifest.Chunks.OrderBy(c => c.Index))
            {
                await using var stream = await _mediator.Send(new DownloadChunkQuery(tenantId, userId, fileId, chunk.Hash), cancellationToken);
                using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
                var buffer = new byte[81920];
                int read;
                while ((read = await stream.ReadAsync(buffer, cancellationToken)) > 0)
                {
                    sha.AppendData(buffer, 0, read);
                    result.Write(buffer, 0, read);
                    if (result.Length > maxBytes)
                        throw new PermanentPhotoException($"File exceeds the {maxBytes} byte limit.");
                }

                // Chunks are named by the SHA-256 of their content.
                if (!string.Equals(Convert.ToHexString(sha.GetHashAndReset()), chunk.Hash, StringComparison.OrdinalIgnoreCase))
                    throw new PermanentPhotoException($"Chunk {chunk.Index} does not match its content hash.");
            }

            if (result.Length != manifest.TotalSize)
                throw new PermanentPhotoException("Assembled size does not match the manifest.");

            return result.ToArray();
        }
        catch (NotFoundException ex)
        {
            throw new PermanentPhotoException($"Original is missing from storage: {ex.Message}", ex);
        }
    }

    public Task PutAsync(Guid tenantId, Guid userId, Guid photoId, int size, byte[] webp, CancellationToken cancellationToken) =>
        _mediator.Send(new PutThumbnailCommand(tenantId, userId, photoId, size, webp), cancellationToken);

    public async Task<Stream?> OpenAsync(Guid tenantId, Guid userId, Guid photoId, int size, CancellationToken cancellationToken)
    {
        try
        {
            return await _mediator.Send(new GetThumbnailQuery(tenantId, userId, photoId, size), cancellationToken);
        }
        catch (NotFoundException)
        {
            return null;
        }
    }
}
