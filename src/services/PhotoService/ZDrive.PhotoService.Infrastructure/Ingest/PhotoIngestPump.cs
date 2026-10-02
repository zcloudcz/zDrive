using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Npgsql;
using ZDrive.PhotoService.Application.Common;
using ZDrive.PhotoService.Application.Interfaces.Ingest;
using ZDrive.PhotoService.Application.Options;
using ZDrive.PhotoService.Domain.Entities;
using ZDrive.PhotoService.Domain.Enums;
using ZDrive.PhotoService.Infrastructure.Persistence;

namespace ZDrive.PhotoService.Infrastructure.Ingest;

/// <summary>
/// Turns FileService's file state into processed photos, in two independent
/// stages so the cursor never waits on image work:
///
///  A. <see cref="ReconcileOnceAsync"/> — makes the <c>photos</c> table match the
///     CURRENT state of the files it is told about (create/queue, hide, un-hide,
///     delete) and advances a durable cursor in the same transaction. Cheap, DB
///     only. A cursor-row lock makes exactly one replica the reader at a time.
///     On a fresh cursor it first bootstraps from the current node state,
///     because the change log starts empty (ADR 0001) and files uploaded before
///     it existed never appear in it; afterwards it follows the feed.
///  B. <see cref="ProcessNextAsync"/> / <see cref="ProcessPendingAsync"/> —
///     claims queued rows (the table is the queue) under a lease and runs
///     metadata extraction + thumbnails.
///
/// State-based rather than event-based: a page with several rows for one
/// file, a row that is older than the file's current state, or a replay after
/// a crash all converge to the same result.
///
/// A photo needs work while <c>SourceManifestHash != ProcessedManifestHash</c>.
/// A photo that already has a processed version stays Processed (and visible,
/// with its current thumbnails) while a newer version is queued or failing.
/// </summary>
public sealed class PhotoIngestPump
{
    private const int BootstrapPageSize = 500;

    private readonly IServiceScopeFactory _scopes;
    private readonly PhotoIngestOptions _options;
    private readonly ILogger<PhotoIngestPump> _logger;

    public PhotoIngestPump(IServiceScopeFactory scopes, IOptions<PhotoIngestOptions> options, ILogger<PhotoIngestPump> logger)
    {
        _scopes = scopes;
        _options = options.Value;
        _logger = logger;
    }

    /// <summary>Runs both stages until neither has work. Used by tests and one-shot backfills.</summary>
    public async Task DrainAsync(CancellationToken cancellationToken)
    {
        while (await ReconcileOnceAsync(cancellationToken)) { }
        while (await ProcessPendingAsync(cancellationToken) > 0) { }
    }

    /// <returns>True when there is more to read right away (more feed rows, or the bootstrap is not finished).</returns>
    public async Task<bool> ReconcileOnceAsync(CancellationToken cancellationToken)
    {
        using var scope = _scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PhotoDbContext>();
        var source = scope.ServiceProvider.GetRequiredService<IFileChangeSource>();

        await using var tx = await db.Database.BeginTransactionAsync(cancellationToken);

        await db.Database.ExecuteSqlRawAsync(
            """
            INSERT INTO photos.ingest_cursors ("Name", "LastChangeId", "UpdatedAt")
            VALUES ('file-changes', 0, now()) ON CONFLICT ("Name") DO NOTHING
            """, cancellationToken);

        // SKIP LOCKED: if another replica is mid-reconcile, this one just skips the round.
        var cursor = (await db.IngestCursors
            .FromSqlRaw("""SELECT * FROM photos.ingest_cursors WHERE "Name" = 'file-changes' FOR UPDATE SKIP LOCKED""")
            .ToListAsync(cancellationToken)).SingleOrDefault();
        if (cursor is null)
            return false;

        bool hasMore;
        List<ChangedFile> files;
        if (cursor.BootstrapCompletedAt is null)
        {
            (files, hasMore) = await BootstrapStepAsync(cursor, source, cancellationToken);
        }
        else
        {
            var batch = await source.ReadBatchAsync(cursor.LastChangeId, _options.BatchSize, cancellationToken);
            files = batch.Files.ToList();
            cursor.LastChangeId = batch.NextCursor;
            hasMore = batch.HasMore;
        }

        var removedPhotos = await ApplyAsync(db, files, cancellationToken);

        cursor.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(cancellationToken);
        await tx.CommitAsync(cancellationToken);

        // After the commit: a failed blob delete only leaves garbage behind,
        // never a photo row pointing at missing thumbnails.
        if (removedPhotos.Count > 0)
        {
            var store = scope.ServiceProvider.GetRequiredService<IThumbnailStore>();
            foreach (var (tenantId, userId, photoId) in removedPhotos)
            {
                try
                {
                    await store.DeleteAllAsync(tenantId, userId, photoId, cancellationToken);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    _logger.LogWarning(ex, "Could not delete thumbnails of removed photo {PhotoId}; left as garbage", photoId);
                }
            }
        }

        _logger.LogDebug("Photo ingest reconciled {Files} file(s), cursor now {Cursor}", files.Count, cursor.LastChangeId);
        return hasMore;
    }

    /// <summary>
    /// One page of the one-time bootstrap. First call captures the safe feed
    /// head (BEFORE looking at any node, so nothing changing meanwhile is
    /// missed: it will be replayed from the feed) and persists it; every call
    /// then scans one keyset page of live file nodes; the last page moves the
    /// cursor to the captured head and marks the bootstrap complete.
    /// </summary>
    private async Task<(List<ChangedFile> Files, bool HasMore)> BootstrapStepAsync(
        IngestCursor cursor, IFileChangeSource source, CancellationToken ct)
    {
        cursor.BootstrapHead ??= await source.ReadSafeHeadAsync(ct);

        var page = await source.ReadNodesAsync(cursor.BootstrapLastNodeId, BootstrapPageSize, ct);
        cursor.BootstrapLastNodeId = page.LastId;

        if (!page.HasMore)
        {
            cursor.LastChangeId = cursor.BootstrapHead.Value;
            cursor.BootstrapCompletedAt = DateTime.UtcNow;
            _logger.LogInformation("Photo ingest bootstrap finished; following the change feed from {Cursor}", cursor.LastChangeId);
        }

        return (page.Files.ToList(), page.HasMore);
    }

    /// <returns>Photos whose rows were deleted (their thumbnails still have to be removed).</returns>
    private static async Task<List<(Guid TenantId, Guid UserId, Guid PhotoId)>> ApplyAsync(
        PhotoDbContext db, IReadOnlyList<ChangedFile> files, CancellationToken ct)
    {
        var fileIds = files.Select(f => f.FileId).ToList();
        var existing = await db.Photos.IgnoreQueryFilters()
            .Where(p => fileIds.Contains(p.FileId))
            .ToDictionaryAsync(p => p.FileId, ct);
        var removed = new List<(Guid, Guid, Guid)>();

        foreach (var file in files)
        {
            existing.TryGetValue(file.FileId, out var photo);
            var node = file.Node;

            if (node is null)
            {
                // Purged: nothing can bring it back, so drop the row (albums and
                // tags cascade) instead of keeping a hidden ghost. EmptyTrash
                // writes no change row (ADR 0001), so this only catches purges
                // seen through a still-pending earlier row; full GC stays future work.
                if (photo is not null)
                {
                    db.Photos.Remove(photo);
                    removed.Add((photo.TenantId, photo.UserId, photo.Id));
                }
                continue;
            }

            var isImage = node is { IsFolder: false, IsDeleted: false, ManifestHash: not null }
                && ImageFileTypes.IsImage(node.Name, node.MimeType);

            if (!isImage)
            {
                // Trashed or no longer an image: hidden but restorable.
                if (photo is { IsHidden: false })
                    photo.IsHidden = true;
                continue;
            }

            if (photo is null)
            {
                photo = new Photo
                {
                    Id = Guid.NewGuid(),
                    FileId = file.FileId,
                    UserId = file.UserId,
                    TenantId = file.TenantId,
                    OriginalFileName = node.Name,
                    BlobPath = $"{file.TenantId}/{file.UserId}/files/{file.FileId}",
                };
                db.Photos.Add(photo);
            }

            photo.IsHidden = false;
            photo.OriginalFileName = node.Name;

            // Idempotency key (FileId, manifestHash): same hash = nothing to redo.
            if (photo.SourceManifestHash != node.ManifestHash)
            {
                photo.SourceManifestHash = node.ManifestHash;
                photo.Attempts = 0;
                photo.FailureReason = null;
                photo.NextAttemptAt = null;
                photo.LockedUntil = null;

                if (photo.ProcessedManifestHash is null)
                {
                    // Never processed yet: not visible until it is; fallback
                    // capture date until EXIF says otherwise.
                    photo.ProcessingStatus = ProcessingStatus.Ingested;
                    photo.TakenAt = FileNameDateParser.TryParse(node.Name) ?? node.CreatedAt;
                }
                // else: keep showing the last good version (status, dates, thumbnails)
                // until the new one has been processed.
            }
        }

        return removed;
    }

    /// <summary>Claims and processes one photo. Several callers run this concurrently.</summary>
    /// <returns>True if a photo was claimed.</returns>
    public async Task<bool> ProcessNextAsync(CancellationToken cancellationToken)
    {
        List<Guid> claimed;
        using (var scope = _scopes.CreateScope())
            claimed = await ClaimAsync(scope.ServiceProvider.GetRequiredService<PhotoDbContext>(), 1, cancellationToken);

        if (claimed.Count == 0)
            return false;

        await ProcessGuardedAsync(claimed[0], cancellationToken);
        return true;
    }

    /// <returns>Number of photos claimed and attempted this round.</returns>
    public async Task<int> ProcessPendingAsync(CancellationToken cancellationToken)
    {
        List<Guid> claimed;
        using (var scope = _scopes.CreateScope())
            claimed = await ClaimAsync(
                scope.ServiceProvider.GetRequiredService<PhotoDbContext>(), _options.MaxConcurrentProcessing, cancellationToken);

        await Parallel.ForEachAsync(
            claimed,
            new ParallelOptions { MaxDegreeOfParallelism = _options.MaxConcurrentProcessing, CancellationToken = cancellationToken },
            async (id, ct) => await ProcessGuardedAsync(id, ct));

        return claimed.Count;
    }

    private async Task ProcessGuardedAsync(Guid id, CancellationToken ct)
    {
        try
        {
            await ProcessOneAsync(id, ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw; // shutdown: the lease simply expires and the row is re-claimed
        }
        catch (Exception ex)
        {
            // Bookkeeping itself failed (DB down). The lease expires and the row is retried.
            _logger.LogError(ex, "Photo {PhotoId}: could not record processing outcome", id);
        }
    }

    private async Task<List<Guid>> ClaimAsync(PhotoDbContext db, int count, CancellationToken ct)
    {
        await db.Database.OpenConnectionAsync(ct);
        try
        {
            await using var cmd = db.Database.GetDbConnection().CreateCommand();
            // Needs work = never processed (Ingested) OR a newer version than the
            // processed one. Attempts caps retries for both; an already-processed
            // photo whose new version keeps failing stops here with Attempts = max.
            // The attempt is counted HERE, at claim time, not after a failure: a
            // photo that crashes the process (OOM, native decoder fault) never
            // reaches RecordFailureAsync, and would otherwise be re-claimed after
            // every lease expiry and take the whole Api down forever.
            cmd.CommandText =
                """
                UPDATE photos.photos SET "LockedUntil" = now() + make_interval(mins => @lease), "Attempts" = "Attempts" + 1
                WHERE "Id" IN (
                    SELECT "Id" FROM photos.photos
                    WHERE NOT "IsHidden" AND "SourceManifestHash" IS NOT NULL
                      AND "Attempts" < @maxAttempts
                      AND ("ProcessingStatus" = 'Ingested'
                           OR ("ProcessingStatus" = 'Processed' AND "SourceManifestHash" IS DISTINCT FROM "ProcessedManifestHash"))
                      AND ("NextAttemptAt" IS NULL OR "NextAttemptAt" <= now())
                      AND ("LockedUntil" IS NULL OR "LockedUntil" < now())
                    ORDER BY "CreatedAt"
                    LIMIT @n
                    FOR UPDATE SKIP LOCKED)
                RETURNING "Id"
                """;
            cmd.Parameters.Add(new NpgsqlParameter("lease", _options.LeaseMinutes));
            cmd.Parameters.Add(new NpgsqlParameter("maxAttempts", _options.MaxAttempts));
            cmd.Parameters.Add(new NpgsqlParameter("n", count));

            var ids = new List<Guid>();
            await using var reader = await cmd.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
                ids.Add(reader.GetGuid(0));
            return ids;
        }
        finally
        {
            await db.Database.CloseConnectionAsync();
        }
    }

    private async Task ProcessOneAsync(Guid id, CancellationToken ct)
    {
        using var scope = _scopes.CreateScope();
        var sp = scope.ServiceProvider;
        var db = sp.GetRequiredService<PhotoDbContext>();

        var photo = await db.Photos.IgnoreQueryFilters().AsNoTracking().FirstOrDefaultAsync(p => p.Id == id, ct);
        if (photo?.SourceManifestHash is not { } manifestHash)
            return;

        try
        {
            var bytes = await sp.GetRequiredService<IPhotoSourceReader>().ReadAsync(
                photo.TenantId, photo.UserId, photo.FileId, manifestHash, _options.MaxSourceBytes, ct);
            var result = sp.GetRequiredService<IPhotoImageProcessor>().Process(bytes);

            // Thumbnail keys carry the version being processed: a slow worker for
            // an older version writes its own keys and can never clobber the
            // thumbnails a newer version is already serving. (Superseded
            // versions' thumbnails are garbage; GC is future work.)
            var store = sp.GetRequiredService<IThumbnailStore>();
            var version = ThumbnailVersion.Of(manifestHash);
            foreach (var (size, webp) in result.Thumbnails)
                await store.PutAsync(photo.TenantId, photo.UserId, photo.Id, version, size, webp, ct);

            var takenAt = result.TakenAtUtc ?? FileNameDateParser.TryParse(photo.OriginalFileName) ?? photo.TakenAt;
            var now = DateTime.UtcNow;
            // Conditional on the hash we processed: if a newer version was
            // queued meanwhile, this is a no-op and the row stays queued for it.
            await db.Photos.IgnoreQueryFilters()
                .Where(p => p.Id == id && p.SourceManifestHash == manifestHash)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(p => p.ProcessingStatus, ProcessingStatus.Processed)
                    .SetProperty(p => p.ProcessedManifestHash, manifestHash)
                    .SetProperty(p => p.ThumbnailsReady, result.Thumbnails.Count > 0)
                    .SetProperty(p => p.TakenAt, takenAt)
                    .SetProperty(p => p.Lat, result.Lat)
                    .SetProperty(p => p.Lng, result.Lng)
                    .SetProperty(p => p.CameraMake, result.CameraMake)
                    .SetProperty(p => p.CameraModel, result.CameraModel)
                    .SetProperty(p => p.Width, result.Width)
                    .SetProperty(p => p.Height, result.Height)
                    .SetProperty(p => p.Orientation, result.Orientation)
                    .SetProperty(p => p.Attempts, 0)
                    .SetProperty(p => p.FailureReason, (string?)null)
                    .SetProperty(p => p.NextAttemptAt, (DateTime?)null)
                    .SetProperty(p => p.LockedUntil, (DateTime?)null)
                    .SetProperty(p => p.ProcessedAt, now), ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (PermanentPhotoException ex)
        {
            _logger.LogWarning("Photo {PhotoId} ({FileId}) failed permanently: {Reason}", id, photo.FileId, ex.Message);
            await RecordFailureAsync(db, photo, manifestHash, ex.Message, permanent: true, ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Photo {PhotoId} ({FileId}) attempt {Attempt} failed", id, photo.FileId, photo.Attempts);
            await RecordFailureAsync(db, photo, manifestHash, $"{ex.GetType().Name}: {ex.Message}", permanent: false, ct);
        }
    }

    private async Task RecordFailureAsync(
        PhotoDbContext db, Photo photo, string manifestHash, string reason, bool permanent, CancellationToken ct)
    {
        // A photo that already has a good version keeps showing it: a failing
        // new version records the reason but never flips it to Failed.
        var hasGoodVersion = photo.ProcessedManifestHash is not null;
        // Already counted by ClaimAsync (photo was loaded after the claim).
        var attempts = photo.Attempts;
        var gaveUp = permanent || attempts >= _options.MaxAttempts;
        var retryAt = gaveUp ? (DateTime?)null : DateTime.UtcNow + (attempts == 1 ? TimeSpan.FromMinutes(1) : TimeSpan.FromMinutes(5));
        var trimmed = reason.Length <= 1000 ? reason : reason[..1000];

        var status = hasGoodVersion
            ? ProcessingStatus.Processed
            : gaveUp ? ProcessingStatus.Failed : ProcessingStatus.Ingested;
        // For a photo with a good version, "given up" must also stop the claim
        // query (it cannot rely on status), so exhaust the attempts.
        var recordedAttempts = hasGoodVersion && gaveUp ? Math.Max(attempts, _options.MaxAttempts) : attempts;

        await db.Photos.IgnoreQueryFilters()
            .Where(p => p.Id == photo.Id && p.SourceManifestHash == manifestHash)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.ProcessingStatus, status)
                .SetProperty(p => p.Attempts, recordedAttempts)
                .SetProperty(p => p.FailureReason, trimmed)
                .SetProperty(p => p.NextAttemptAt, retryAt)
                .SetProperty(p => p.LockedUntil, (DateTime?)null), ct);
    }
}
