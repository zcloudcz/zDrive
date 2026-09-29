namespace ZDrive.PhotoService.Application.Interfaces.Ingest;

public interface IThumbnailStore
{
    Task PutAsync(Guid tenantId, Guid userId, Guid photoId, int size, byte[] webp, CancellationToken cancellationToken);

    /// <summary>Null when the thumbnail blob does not exist.</summary>
    Task<Stream?> OpenAsync(Guid tenantId, Guid userId, Guid photoId, int size, CancellationToken cancellationToken);
}
