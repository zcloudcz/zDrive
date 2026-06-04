using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.SyncService.Application.DTOs;
using ZDrive.SyncService.Application.Interfaces;

namespace ZDrive.SyncService.Application.Queries.GetConflicts;

public sealed class GetConflictsQueryHandler : IRequestHandler<GetConflictsQuery, List<SyncConflictDto>>
{
    private readonly ISyncDbContext _db;

    public GetConflictsQueryHandler(ISyncDbContext db) => _db = db;

    public async Task<List<SyncConflictDto>> Handle(GetConflictsQuery request, CancellationToken cancellationToken)
    {
        var conflicts = await _db.SyncConflicts
            .AsNoTracking()
            .Where(c => c.UserId == request.UserId)
            .OrderByDescending(c => c.CreatedAt)
            .ToListAsync(cancellationToken);

        return conflicts.Select(c => c.ToDto()).ToList();
    }
}
