using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;

namespace ZDrive.FileService.Application.Queries.GetFileChanges;

public sealed class GetFileChangesQueryHandler : IRequestHandler<GetFileChangesQuery, FileChangesPageDto>
{
    // Identity values are assigned at insert time, not at commit time: a
    // transaction that took id N+1 can still commit after one that took id
    // N+2. A reader who saw N+2 and advanced its cursor past it would skip
    // N+1 forever. Holding back anything younger than this closes that
    // window for any transaction shorter than it — known limit, see the ADR.
    private static readonly TimeSpan CommitOrderHoldBack = TimeSpan.FromSeconds(5);

    private readonly IFileDbContext _db;
    private readonly TimeProvider _timeProvider;

    public GetFileChangesQueryHandler(IFileDbContext db, TimeProvider timeProvider)
    {
        _db = db;
        _timeProvider = timeProvider;
    }

    public async Task<FileChangesPageDto> Handle(GetFileChangesQuery request, CancellationToken cancellationToken)
    {
        var cutoff = _timeProvider.GetUtcNow().UtcDateTime - CommitOrderHoldBack;

        var query = _db.FileChanges
            .AsNoTracking()
            .Where(c =>
                c.TenantId == request.TenantId
                && c.UserId == request.UserId
                && c.Id > request.Cursor
                && c.OccurredAt <= cutoff);

        // EF's default null semantics turn this into "<> @p OR IS NULL", so a
        // row with no origin still passes — only an exact device match is excluded.
        if (request.RequestingDeviceId.HasValue)
            query = query.Where(c => c.OriginDeviceId != request.RequestingDeviceId);

        var rows = await query
            .OrderBy(c => c.Id)
            .Take(request.Limit)
            .ToListAsync(cancellationToken);

        var changes = rows.Select(c => c.ToDto()).ToList();
        var nextCursor = rows.Count > 0 ? rows[^1].Id : request.Cursor;

        return new FileChangesPageDto(changes, nextCursor, rows.Count == request.Limit);
    }
}
