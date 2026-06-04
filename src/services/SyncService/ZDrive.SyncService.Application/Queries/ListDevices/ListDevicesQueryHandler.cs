using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.SyncService.Application.DTOs;
using ZDrive.SyncService.Application.Interfaces;

namespace ZDrive.SyncService.Application.Queries.ListDevices;

public sealed class ListDevicesQueryHandler : IRequestHandler<ListDevicesQuery, List<DeviceDto>>
{
    private readonly ISyncDbContext _db;

    public ListDevicesQueryHandler(ISyncDbContext db) => _db = db;

    public async Task<List<DeviceDto>> Handle(ListDevicesQuery request, CancellationToken cancellationToken)
    {
        var devices = await _db.Devices
            .AsNoTracking()
            .Where(d => d.UserId == request.UserId)
            .OrderByDescending(d => d.CreatedAt)
            .ToListAsync(cancellationToken);

        return devices.Select(d => d.ToDto()).ToList();
    }
}
