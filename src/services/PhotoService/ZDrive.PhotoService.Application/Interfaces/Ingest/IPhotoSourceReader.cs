namespace ZDrive.PhotoService.Application.Interfaces.Ingest;

public interface IPhotoSourceReader
{
    /// <summary>
    /// Reads the original of one immutable version (manifest snapshot +
    /// chunks), verifying every chunk against its content hash.
    /// Throws <see cref="PermanentPhotoException"/> when retrying cannot help.
    /// </summary>
    Task<byte[]> ReadAsync(
        Guid tenantId, Guid userId, Guid fileId, string manifestHash, long maxBytes, CancellationToken cancellationToken);
}
