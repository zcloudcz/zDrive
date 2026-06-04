using MediatR;
using ZDrive.SyncService.Application.DTOs;
using ZDrive.SyncService.Application.Interfaces;
using ZDrive.SyncService.Domain.Entities;

namespace ZDrive.SyncService.Application.Commands.RegisterDevice;

public sealed class RegisterDeviceCommandHandler : IRequestHandler<RegisterDeviceCommand, DeviceDto>
{
    private readonly ISyncDbContext _db;

    public RegisterDeviceCommandHandler(ISyncDbContext db) => _db = db;

    public async Task<DeviceDto> Handle(RegisterDeviceCommand request, CancellationToken cancellationToken)
    {
        var device = new Device
        {
            Id = Guid.NewGuid(),
            UserId = request.UserId,
            Name = request.Name,
            Platform = request.Platform,
            SyncCursor = 0
        };

        _db.Devices.Add(device);
        await _db.SaveChangesAsync(cancellationToken);

        return device.ToDto();
    }
}
