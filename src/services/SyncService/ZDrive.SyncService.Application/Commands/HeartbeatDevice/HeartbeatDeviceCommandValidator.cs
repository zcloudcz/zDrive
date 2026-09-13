using FluentValidation;

namespace ZDrive.SyncService.Application.Commands.HeartbeatDevice;

public sealed class HeartbeatDeviceCommandValidator : AbstractValidator<HeartbeatDeviceCommand>
{
    public HeartbeatDeviceCommandValidator()
    {
        RuleFor(x => x.UserId).NotEmpty();
        RuleFor(x => x.DeviceId).NotEmpty();
    }
}
