using ZDrive.PhotoService.Application.Interfaces.Ingest;

namespace ZDrive.PhotoService.Tests.Integration;

/// <summary>Delegates to the real store but can fail writes or pause them (to interleave workers).</summary>
internal sealed class FlakyThumbnailStore(
    IThumbnailStore inner, Func<bool> shouldFail, Func<Func<string, Task>?> beforeWrite) : IThumbnailStore
{
    public async Task PutAsync(Guid tenantId, Guid userId, Guid photoId, string version, int size, byte[] webp, CancellationToken cancellationToken)
    {
        if (beforeWrite() is { } hook)
            await hook(version);
        if (shouldFail())
            throw new IOException("Simulated thumbnail write failure.");
        await inner.PutAsync(tenantId, userId, photoId, version, size, webp, cancellationToken);
    }

    public Task<Stream?> OpenAsync(Guid tenantId, Guid userId, Guid photoId, string version, int size, CancellationToken cancellationToken) =>
        inner.OpenAsync(tenantId, userId, photoId, version, size, cancellationToken);

    public Task DeleteAllAsync(Guid tenantId, Guid userId, Guid photoId, CancellationToken cancellationToken) =>
        inner.DeleteAllAsync(tenantId, userId, photoId, cancellationToken);
}
