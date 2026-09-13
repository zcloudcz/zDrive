using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.SyncService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.SyncService.Application.Commands.HeartbeatDevice;

public sealed class HeartbeatDeviceCommandHandler : IRequestHandler<HeartbeatDeviceCommand, bool>
{
    private readonly ISyncDbContext _db;

    public HeartbeatDeviceCommandHandler(ISyncDbContext db) => _db = db;

    public async Task<bool> Handle(HeartbeatDeviceCommand request, CancellationToken cancellationToken)
    {
        var device = await _db.Devices
            .FirstOrDefaultAsync(d => d.Id == request.DeviceId && d.UserId == request.UserId, cancellationToken)
            ?? throw new NotFoundException("Device", request.DeviceId);

        device.LastSyncAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(cancellationToken);

        return true;
    }
}
