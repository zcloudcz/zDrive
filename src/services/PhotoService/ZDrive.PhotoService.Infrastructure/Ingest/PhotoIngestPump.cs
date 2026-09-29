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
/// Turns FileService's global change feed into processed photos, in two
/// independent stages so the cursor never waits on image work:
///
///  A. <see cref="ReconcileOnceAsync"/> — reads one feed page and makes the
///     <c>photos</c> table match the CURRENT state of every file it names
///     (create/queue, hide, unhide), then advances the durable cursor in the
///     same transaction. Cheap, DB only. A cursor-row lock makes exactly one
///     replica the reader at a time.
///  B. <see cref="ProcessPendingAsync"/> — claims queued rows (the table is
///     the queue) under a lease and runs metadata extraction + thumbnails.
///
/// State-based rather than event-based: a page with several rows for one
/// file, a row that is older than the file's current state, or a replay after
/// a crash all converge to the same result.
/// </summary>
public sealed class PhotoIngestPump
{
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

    /// <returns>True when the feed has more rows to read right away.</returns>
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

        var batch = await source.ReadBatchAsync(cursor.LastChangeId, _options.BatchSize, cancellationToken);

        var fileIds = batch.Files.Select(f => f.FileId).ToList();
        var existing = await db.Photos.IgnoreQueryFilters()
            .Where(p => fileIds.Contains(p.FileId))
            .ToDictionaryAsync(p => p.FileId, cancellationToken);

        foreach (var file in batch.Files)
        {
            existing.TryGetValue(file.FileId, out var photo);
            var node = file.Node;
            var isImage = node is { IsFolder: false, IsDeleted: false, ManifestHash: not null }
                && ImageFileTypes.IsImage(node.Name, node.MimeType);

            if (!isImage)
            {
                // Trashed, purged, or no longer an image.
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
                    OriginalFileName = node!.Name,
                    BlobPath = $"{file.TenantId}/{file.UserId}/files/{file.FileId}",
                };
                db.Photos.Add(photo);
            }

            photo.IsHidden = false;
            photo.OriginalFileName = node!.Name;

            // Idempotency key (FileId, manifestHash): same hash = nothing to redo.
            if (photo.SourceManifestHash != node.ManifestHash)
            {
                photo.SourceManifestHash = node.ManifestHash;
                photo.ProcessingStatus = ProcessingStatus.Ingested;
                photo.Attempts = 0;
                photo.FailureReason = null;
                photo.NextAttemptAt = null;
                photo.LockedUntil = null;
                // Fallback capture date until EXIF says otherwise.
                photo.TakenAt = FileNameDateParser.TryParse(node.Name) ?? node.CreatedAt;
            }
        }

        cursor.LastChangeId = batch.NextCursor;
        cursor.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(cancellationToken);
        await tx.CommitAsync(cancellationToken);

        _logger.LogDebug("Photo ingest reconciled {Files} file(s), cursor now {Cursor}", batch.Files.Count, batch.NextCursor);
        return batch.HasMore;
    }

    /// <returns>Number of photos claimed and attempted this round.</returns>
    public async Task<int> ProcessPendingAsync(CancellationToken cancellationToken)
    {
        List<Guid> claimed;
        using (var scope = _scopes.CreateScope())
            claimed = await ClaimAsync(scope.ServiceProvider.GetRequiredService<PhotoDbContext>(), cancellationToken);

        await Parallel.ForEachAsync(
            claimed,
            new ParallelOptions { MaxDegreeOfParallelism = _options.MaxConcurrentProcessing, CancellationToken = cancellationToken },
            async (id, ct) =>
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
            });

        return claimed.Count;
    }

    private async Task<List<Guid>> ClaimAsync(PhotoDbContext db, CancellationToken ct)
    {
        await db.Database.OpenConnectionAsync(ct);
        try
        {
            await using var cmd = db.Database.GetDbConnection().CreateCommand();
            cmd.CommandText =
                """
                UPDATE photos.photos SET "LockedUntil" = now() + make_interval(mins => @lease)
                WHERE "Id" IN (
                    SELECT "Id" FROM photos.photos
                    WHERE "ProcessingStatus" = 'Ingested' AND NOT "IsHidden" AND "SourceManifestHash" IS NOT NULL
                      AND ("NextAttemptAt" IS NULL OR "NextAttemptAt" <= now())
                      AND ("LockedUntil" IS NULL OR "LockedUntil" < now())
                    ORDER BY "CreatedAt"
                    LIMIT @n
                    FOR UPDATE SKIP LOCKED)
                RETURNING "Id"
                """;
            cmd.Parameters.Add(new NpgsqlParameter("lease", _options.LeaseMinutes));
            cmd.Parameters.Add(new NpgsqlParameter("n", _options.MaxConcurrentProcessing));

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

            var store = sp.GetRequiredService<IThumbnailStore>();
            foreach (var (size, webp) in result.Thumbnails)
                await store.PutAsync(photo.TenantId, photo.UserId, photo.Id, size, webp, ct);

            var takenAt = result.TakenAtUtc ?? photo.TakenAt;
            var now = DateTime.UtcNow;
            // Conditional on the hash we processed: if a newer version was
            // queued meanwhile, this is a no-op and the row stays Ingested.
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
                    .SetProperty(p => p.FailureReason, (string?)null)
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
            _logger.LogWarning(ex, "Photo {PhotoId} ({FileId}) attempt {Attempt} failed", id, photo.FileId, photo.Attempts + 1);
            await RecordFailureAsync(db, photo, manifestHash, $"{ex.GetType().Name}: {ex.Message}", permanent: false, ct);
        }
    }

    private async Task RecordFailureAsync(
        PhotoDbContext db, Photo photo, string manifestHash, string reason, bool permanent, CancellationToken ct)
    {
        var attempts = photo.Attempts + 1;
        var failed = permanent || attempts >= _options.MaxAttempts;
        var retryAt = failed ? (DateTime?)null : DateTime.UtcNow + (attempts == 1 ? TimeSpan.FromMinutes(1) : TimeSpan.FromMinutes(5));
        var trimmed = reason.Length <= 1000 ? reason : reason[..1000];

        await db.Photos.IgnoreQueryFilters()
            .Where(p => p.Id == photo.Id && p.SourceManifestHash == manifestHash)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.ProcessingStatus, failed ? ProcessingStatus.Failed : ProcessingStatus.Ingested)
                .SetProperty(p => p.Attempts, attempts)
                .SetProperty(p => p.FailureReason, trimmed)
                .SetProperty(p => p.NextAttemptAt, retryAt)
                .SetProperty(p => p.LockedUntil, (DateTime?)null), ct);
    }
}
