using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.SyncService.Application.DTOs;
using ZDrive.SyncService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.SyncService.Application.Queries.PullChanges;

public sealed class PullChangesQueryHandler : IRequestHandler<PullChangesQuery, PullResultDto>
{
    private const int MaxEventsPerPull = 500;

    private readonly ISyncDbContext _db;

    public PullChangesQueryHandler(ISyncDbContext db) => _db = db;

    public async Task<PullResultDto> Handle(PullChangesQuery request, CancellationToken cancellationToken)
    {
        // Verify the device exists and belongs to the user.
        var deviceExists = await _db.Devices
            .AnyAsync(d => d.Id == request.DeviceId && d.UserId == request.UserId, cancellationToken);

        if (!deviceExists)
            throw new NotFoundException("Device", request.DeviceId);

        // Fetch events after the cursor, excluding events from the requesting device.
        var events = await _db.SyncEvents
            .AsNoTracking()
            .Where(e =>
                e.UserId == request.UserId
                && e.Id > request.Cursor
                && e.DeviceId != request.DeviceId)
            .OrderBy(e => e.Id)
            .Take(MaxEventsPerPull)
            .ToListAsync(cancellationToken);

        var newCursor = events.Count > 0
            ? events[^1].Id
            : request.Cursor;

        return new PullResultDto(
            events.Select(e => e.ToDto()).ToList(),
            newCursor);
    }
}
