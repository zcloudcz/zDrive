using MediatR;
using ZDrive.SyncService.Application.DTOs;

namespace ZDrive.SyncService.Application.Queries.ListDevices;

public sealed record ListDevicesQuery(Guid UserId) : IRequest<List<DeviceDto>>;
