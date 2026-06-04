using MediatR;
using ZDrive.SyncService.Application.DTOs;
using ZDrive.SyncService.Domain.Enums;

namespace ZDrive.SyncService.Application.Commands.RegisterDevice;

public sealed record RegisterDeviceCommand(
    Guid UserId,
    string Name,
    DevicePlatform Platform) : IRequest<DeviceDto>;
