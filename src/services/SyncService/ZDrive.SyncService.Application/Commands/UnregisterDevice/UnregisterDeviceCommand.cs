using MediatR;

namespace ZDrive.SyncService.Application.Commands.UnregisterDevice;

public sealed record UnregisterDeviceCommand(
    Guid UserId,
    Guid DeviceId) : IRequest<bool>;
