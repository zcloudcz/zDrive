namespace ZDrive.PhotoService.Application.Interfaces.Ingest;

/// <summary>
/// Port onto FileService's global change feed. Implemented in the Api host
/// (the only place that may reference both modules) over FileService's
/// MediatR queries, so the Photo module never touches another module's
/// DbContext.
/// </summary>
public interface IFileChangeSource
{
    Task<FileChangeBatch> ReadBatchAsync(long cursor, int limit, CancellationToken cancellationToken);

    /// <summary>Highest feed id such that everything up to it is committed and past the hold-back.</summary>
    Task<long> ReadSafeHeadAsync(CancellationToken cancellationToken);

    /// <summary>Keyset-paged scan of all live, non-folder nodes (bootstrap). <see cref="FileNodePage.LastId"/> feeds the next call.</summary>
    Task<FileNodePage> ReadNodesAsync(Guid? afterId, int limit, CancellationToken cancellationToken);
}

/// <summary>Files touched by one page of the feed (one entry per file), plus the cursor to persist.</summary>
public sealed record FileChangeBatch(IReadOnlyList<ChangedFile> Files, long NextCursor, bool HasMore);

public sealed record FileNodePage(IReadOnlyList<ChangedFile> Files, Guid? LastId, bool HasMore);

/// <param name="Node">Current state of the file; null when the node no longer exists (hard-deleted).</param>
public sealed record ChangedFile(Guid FileId, Guid TenantId, Guid UserId, FileSnapshot? Node);

public sealed record FileSnapshot(
    string Name,
    string? MimeType,
    bool IsFolder,
    bool IsDeleted,
    string? ManifestHash,
    DateTime CreatedAt);
