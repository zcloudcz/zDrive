using ZDrive.PhotoService.Application.Interfaces.Ingest;

namespace ZDrive.PhotoService.Tests.Integration;

/// <summary>Delegates to the real store but can be told to fail writes.</summary>
internal sealed class FlakyThumbnailStore(IThumbnailStore inner, Func<bool> shouldFail) : IThumbnailStore
{
    public Task PutAsync(Guid tenantId, Guid userId, Guid photoId, int size, byte[] webp, CancellationToken cancellationToken) =>
        shouldFail()
            ? throw new IOException("Simulated thumbnail write failure.")
            : inner.PutAsync(tenantId, userId, photoId, size, webp, cancellationToken);

    public Task<Stream?> OpenAsync(Guid tenantId, Guid userId, Guid photoId, int size, CancellationToken cancellationToken) =>
        inner.OpenAsync(tenantId, userId, photoId, size, cancellationToken);
}
