using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;

namespace ZDrive.FileService.Application.Queries.GetFileChanges;

public sealed class GetFileChangesQueryHandler : IRequestHandler<GetFileChangesQuery, FileChangesPageDto>
{
    // Identity values are assigned at insert time, not at commit time: a
    // transaction that took id N+1 can still commit after one that took id
    // N+2. Holding back anything younger than this closes that window for
    // any transaction shorter than it — known limit, see the ADR.
    private static readonly TimeSpan CommitOrderHoldBack = TimeSpan.FromSeconds(5);

    private readonly IFileDbContext _db;

    public GetFileChangesQueryHandler(IFileDbContext db)
    {
        _db = db;
    }

    public async Task<FileChangesPageDto> Handle(GetFileChangesQuery request, CancellationToken cancellationToken)
    {
        // Read one row past the limit, in id order (= commit order, since
        // ids are assigned inside SaveChanges before commit and never
        // reused), with no per-row time filter yet — a per-row filter is
        // exactly bug B1: a row can be young (occurred_at close to "now")
        // while a HIGHER-id row that committed later happens to have an
        // OLDER stamp, and a per-row filter would let that older-stamped
        // row through while holding back the younger one behind it,
        // advancing the cursor past the younger row forever.
        //
        // TooYoung is computed here, server-side, against the one Postgres
        // clock (Npgsql translates DateTime.UtcNow to now()) rather than
        // this handler's own process clock — two FileService instances with
        // skewed clocks must not disagree about which rows are held back.
        var cutoff = DateTime.UtcNow - CommitOrderHoldBack;

        var rows = await _db.FileChanges
            .AsNoTracking()
            .Where(c =>
                c.TenantId == request.TenantId
                && c.UserId == request.UserId
                && c.Id > request.Cursor)
            .OrderBy(c => c.Id)
            .Take(request.Limit + 1)
            .Select(c => new { Change = c, TooYoung = c.OccurredAt > cutoff })
            .ToListAsync(cancellationToken);

        // Hold back a PREFIX of the id order, not individual rows: once the
        // first too-young row is hit, everything after it (by id) is held
        // back too, regardless of its own timestamp. That is what actually
        // closes the skip window — a filter that let a later, older-stamped
        // row through while dropping an earlier, younger one is the bug this
        // replaces.
        var firstTooYoungIndex = rows.FindIndex(r => r.TooYoung);
        var prefixLength = Math.Min(
            firstTooYoungIndex >= 0 ? firstTooYoungIndex : rows.Count,
            request.Limit);

        var prefix = rows.Take(prefixLength).Select(r => r.Change).ToList();

        // nextCursor advances to the last row of the prefix even though some
        // of those rows are about to be dropped below for being the caller's
        // own device. An excluded row still moved the cursor past it — so a
        // caller whose only remaining rows are its own writes doesn't
        // re-scan that same growing tail on every poll (review finding B2).
        var nextCursor = prefix.Count > 0 ? prefix[^1].Id : request.Cursor;

        // EF's default null semantics turn this into "<> @p OR IS NULL", so a
        // row with no origin still passes — only an exact device match is
        // excluded. Done in memory, after nextCursor is already fixed above,
        // so exclusion never affects paging.
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
