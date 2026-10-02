using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Domain.Entities;

namespace ZDrive.FileService.Application.Queries.GetFileChanges;

/// <summary>
/// The one implementation of the ADR 0001 read semantics — SHARE-locked read
/// scope, id-ordered page, prefix hold-back — shared by the per-user feed
/// (<see cref="GetFileChangesQueryHandler"/>) and the global feed the photo
/// ingest worker consumes (GetFileChangeBatchQueryHandler). Only the
/// <paramref name="scope"/> filter differs between them.
/// </summary>
internal static class FileChangeFeedReader
{
    // Preserve the existing feed delay. Commit-order correctness comes from
    // the read scope below, independently of how long a writer takes.
    private static readonly TimeSpan CommitOrderHoldBack = TimeSpan.FromSeconds(5);

    internal sealed record Page(List<FileChange> Prefix, long NextCursor, bool HasMore);

    internal static async Task<Page> ReadAsync(
        IFileDbContext db,
        Func<IQueryable<FileChange>, IQueryable<FileChange>> scope,
        long cursor,
        int limit,
        CancellationToken cancellationToken)
    {
        // READ COMMITTED takes the query snapshot after the SHARE lock has
        // waited for outstanding inserts. Disposal releases it on every exit.
        await using var readScope = await db.BeginFileChangeReadAsync(cancellationToken);

        // Read one row past the limit in id order. Id order is NOT commit
        // order, which is why there is no
        // per-row time filter here: a row can still be young while a
        // higher-id row carries an older stamp, and a per-row filter would
        // let the higher id through and move the cursor past the younger
        // row for good. Where to stop is decided below, as a prefix.
        var rows = await scope(db.FileChanges.AsNoTracking())
            .Where(c => c.Id > cursor)
            .OrderBy(c => c.Id)
            .Take(limit + 1)
            // Must stay inside the expression: Npgsql translates DateTime.UtcNow
            // to the database's now(), the same clock that stamped occurred_at.
            // A cutoff computed in C# would compare the app server's clock
            // against the database's, and skew would shrink the hold-back.
            .Select(c => new { Change = c, TooYoung = c.OccurredAt > DateTime.UtcNow.AddSeconds(-CommitOrderHoldBack.TotalSeconds) })
            .ToListAsync(cancellationToken);

        // Hold back a PREFIX of the id order, not individual rows: once the
        // first too-young row is hit, everything after it (by id) is held
        // back too, regardless of its own timestamp. That is what actually
        // closes the skip window — a filter that let a later, older-stamped
        // row through while dropping an earlier, younger one would move the
        // cursor past the younger row for good.
        var firstTooYoungIndex = rows.FindIndex(r => r.TooYoung);
        var prefixLength = Math.Min(
            firstTooYoungIndex >= 0 ? firstTooYoungIndex : rows.Count,
            limit);

        var prefix = rows.Take(prefixLength).Select(r => r.Change).ToList();
        var nextCursor = prefix.Count > 0 ? prefix[^1].Id : cursor;

        // More to read right away only if the prefix used the full page AND
        // the raw window actually held more rows beyond it (either more ids
        // or ids held back as too young).
        var hasMore = prefixLength == limit && rows.Count > prefixLength;

        return new Page(prefix, nextCursor, hasMore);
    }

    /// <summary>
    /// Highest id such that EVERY row up to and including it is committed and
    /// past the hold-back — the position a consumer may safely start reading
    /// from after it has looked at the current state of all nodes. Same read
    /// scope and prefix rule as <see cref="ReadAsync"/>: it is the id just
    /// before the first row that is still too young. 0 when the log is empty.
    /// </summary>
    internal static async Task<long> ReadSafeHeadAsync(IFileDbContext db, CancellationToken cancellationToken)
    {
        await using var readScope = await db.BeginFileChangeReadAsync(cancellationToken);

        var firstTooYoung = await db.FileChanges.AsNoTracking()
            .Where(c => c.OccurredAt > DateTime.UtcNow.AddSeconds(-CommitOrderHoldBack.TotalSeconds))
            .MinAsync(c => (long?)c.Id, cancellationToken);

        var below = db.FileChanges.AsNoTracking()
            .Where(c => firstTooYoung == null || c.Id < firstTooYoung);
        return await below.MaxAsync(c => (long?)c.Id, cancellationToken) ?? 0;
    }
}
