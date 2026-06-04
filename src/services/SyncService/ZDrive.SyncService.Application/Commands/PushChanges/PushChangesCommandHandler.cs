using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.SyncService.Application.DTOs;
using ZDrive.SyncService.Application.Interfaces;
using ZDrive.SyncService.Domain.Entities;
using ZDrive.SyncService.Domain.Enums;
using ZDrive.Shared.Exceptions;

namespace ZDrive.SyncService.Application.Commands.PushChanges;

public sealed class PushChangesCommandHandler : IRequestHandler<PushChangesCommand, PushResultDto>
{
    private readonly ISyncDbContext _db;

    public PushChangesCommandHandler(ISyncDbContext db) => _db = db;

    public async Task<PushResultDto> Handle(PushChangesCommand request, CancellationToken cancellationToken)
    {
        var device = await _db.Devices
            .FirstOrDefaultAsync(d => d.Id == request.DeviceId && d.UserId == request.UserId, cancellationToken)
            ?? throw new NotFoundException("Device", request.DeviceId);

        var conflicts = new List<SyncConflictDto>();
        long newCursor = device.SyncCursor;

        foreach (var item in request.Events)
        {
            // Detect conflicts: check if another device pushed an event for the same file
            // since this device's last sync cursor.
            var conflictingEvent = await _db.SyncEvents
                .Where(e =>
                    e.UserId == request.UserId
                    && e.FileId == item.FileId
                    && e.DeviceId != request.DeviceId
                    && e.Id > device.SyncCursor)
                .OrderByDescending(e => e.Id)
                .FirstOrDefaultAsync(cancellationToken);

            if (conflictingEvent is not null)
            {
                var conflict = new SyncConflict
                {
                    Id = Guid.NewGuid(),
                    UserId = request.UserId,
                    FileId = item.FileId,
                    LocalDeviceId = request.DeviceId,
                    RemoteDeviceId = conflictingEvent.DeviceId,
                    LocalVersion = device.SyncCursor,
                    RemoteVersion = conflictingEvent.Id,
                    Status = ConflictStatus.Pending
                };

                _db.SyncConflicts.Add(conflict);
                conflicts.Add(conflict.ToDto());
                continue;
            }

            var syncEvent = new SyncEvent
            {
                UserId = request.UserId,
                DeviceId = request.DeviceId,
                FileId = item.FileId,
                EventType = item.EventType,
                Metadata = item.Metadata
            };

            _db.SyncEvents.Add(syncEvent);
        }

        await _db.SaveChangesAsync(cancellationToken);

        // Get the latest event ID for this user to compute the new cursor.
        var latestEventId = await _db.SyncEvents
            .Where(e => e.UserId == request.UserId)
            .OrderByDescending(e => e.Id)
            .Select(e => e.Id)
            .FirstOrDefaultAsync(cancellationToken);

        newCursor = latestEventId;

        device.SyncCursor = newCursor;
        device.LastSyncAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(cancellationToken);

        return new PushResultDto(newCursor, conflicts);
    }
}
