using MediatR;

namespace ZDrive.SyncService.Application.Commands.HeartbeatDevice;

public sealed record HeartbeatDeviceCommand(
    Guid UserId,
    Guid DeviceId) : IRequest<bool>;
