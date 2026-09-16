using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;

namespace ZDrive.FileService.Application.Queries.GetFileChanges;

public sealed class GetFileChangesQueryHandler : IRequestHandler<GetFileChangesQuery, FileChangesPageDto>
{
    // Preserve the existing feed delay. Commit-order correctness comes from
    // the read scope below, independently of how long a writer takes.
    private static readonly TimeSpan CommitOrderHoldBack = TimeSpan.FromSeconds(5);

    private readonly IFileDbContext _db;

    public GetFileChangesQueryHandler(IFileDbContext db)
    {
        _db = db;
    }

    public async Task<FileChangesPageDto> Handle(GetFileChangesQuery request, CancellationToken cancellationToken)
    {
        // READ COMMITTED takes the query snapshot after the SHARE lock has
        // waited for outstanding inserts. Disposal releases it on every exit.
        await using var readScope = await _db.BeginFileChangeReadAsync(cancellationToken);

        // Read one row past the limit in id order. Id order is NOT commit
        // order, which is why there is no
        // per-row time filter here: a row can still be young while a
        // higher-id row carries an older stamp, and a per-row filter would
        // let the higher id through and move the cursor past the younger
        // row for good. Where to stop is decided below, as a prefix.

        var rows = await _db.FileChanges
            .AsNoTracking()
            .Where(c =>
                c.TenantId == request.TenantId
                && c.UserId == request.UserId
                && c.Id > request.Cursor)
            .OrderBy(c => c.Id)
            .Take(request.Limit + 1)
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
            request.Limit);

        var prefix = rows.Take(prefixLength).Select(r => r.Change).ToList();

        // nextCursor advances to the last row of the prefix even though some
        // of those rows are about to be dropped below for being the caller's
        // own device. An excluded row still moved the cursor past it — so a
        // caller whose only remaining rows are its own writes doesn't
        // re-scan that same growing tail on every poll.
        var nextCursor = prefix.Count > 0 ? prefix[^1].Id : request.Cursor;

        // In memory, after nextCursor is already fixed above, so exclusion
        // never affects paging. A row with no origin (null) never equals a
        // device id, so it passes — only an exact device match is excluded.
        var visible = request.RequestingDeviceId.HasValue
            ? prefix.Where(c => c.OriginDeviceId != request.RequestingDeviceId)
            : prefix;

        var changes = visible.Select(c => c.ToDto()).ToList();

        // More to read right away only if the prefix used the full page AND
        // the raw window actually held more rows beyond it (either more ids
        // or ids held back as too young).
        var hasMore = prefixLength == request.Limit && rows.Count > prefixLength;

        return new FileChangesPageDto(changes, nextCursor, hasMore);
    }
}
