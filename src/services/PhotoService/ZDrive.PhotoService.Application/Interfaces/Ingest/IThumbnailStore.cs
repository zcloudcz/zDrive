namespace ZDrive.PhotoService.Application.Interfaces.Ingest;

public interface IThumbnailStore
{
    /// <param name="version">Source version key (see <c>ThumbnailVersion.Of</c>): a late writer for an older version cannot touch a newer one's thumbnails.</param>
    Task PutAsync(Guid tenantId, Guid userId, Guid photoId, string version, int size, byte[] webp, CancellationToken cancellationToken);

    /// <summary>Null when the thumbnail blob does not exist.</summary>
    Task<Stream?> OpenAsync(Guid tenantId, Guid userId, Guid photoId, string version, int size, CancellationToken cancellationToken);

    /// <summary>Removes every thumbnail of a photo (all versions).</summary>
    Task DeleteAllAsync(Guid tenantId, Guid userId, Guid photoId, CancellationToken cancellationToken);
}
