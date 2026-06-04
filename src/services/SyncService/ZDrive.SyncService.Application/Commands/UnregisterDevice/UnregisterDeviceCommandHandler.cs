using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.SyncService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.SyncService.Application.Commands.UnregisterDevice;

public sealed class UnregisterDeviceCommandHandler : IRequestHandler<UnregisterDeviceCommand, bool>
{
    private readonly ISyncDbContext _db;

    public UnregisterDeviceCommandHandler(ISyncDbContext db) => _db = db;

    public async Task<bool> Handle(UnregisterDeviceCommand request, CancellationToken cancellationToken)
    {
        var device = await _db.Devices
            .FirstOrDefaultAsync(d => d.Id == request.DeviceId && d.UserId == request.UserId, cancellationToken)
            ?? throw new NotFoundException("Device", request.DeviceId);

        _db.Devices.Remove(device);
        await _db.SaveChangesAsync(cancellationToken);

        return true;
    }
}
