using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.SyncService.Application.Interfaces;
using ZDrive.SyncService.Domain.Enums;
using ZDrive.Shared.Exceptions;

namespace ZDrive.SyncService.Application.Commands.ResolveConflict;

public sealed class ResolveConflictCommandHandler : IRequestHandler<ResolveConflictCommand, bool>
{
    private readonly ISyncDbContext _db;

    public ResolveConflictCommandHandler(ISyncDbContext db) => _db = db;

    public async Task<bool> Handle(ResolveConflictCommand request, CancellationToken cancellationToken)
    {
        var conflict = await _db.SyncConflicts
            .FirstOrDefaultAsync(c =>
                c.Id == request.ConflictId
                && c.UserId == request.UserId
                && c.Status == ConflictStatus.Pending,
                cancellationToken)
            ?? throw new NotFoundException("SyncConflict", request.ConflictId);

        conflict.Status = request.Resolution switch
        {
            ConflictResolution.KeepLocal => ConflictStatus.ResolvedLocal,
            ConflictResolution.KeepRemote => ConflictStatus.ResolvedRemote,
            ConflictResolution.KeepBoth => ConflictStatus.ResolvedMerge,
            _ => throw new ArgumentOutOfRangeException(nameof(request.Resolution))
        };
        conflict.ResolvedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync(cancellationToken);

        return true;
    }
}
