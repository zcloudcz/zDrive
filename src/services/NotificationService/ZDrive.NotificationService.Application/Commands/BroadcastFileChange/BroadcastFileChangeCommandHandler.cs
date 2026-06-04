using MediatR;
using ZDrive.NotificationService.Application.DTOs;
using ZDrive.NotificationService.Application.Interfaces;

namespace ZDrive.NotificationService.Application.Commands.BroadcastFileChange;

public sealed class BroadcastFileChangeCommandHandler : IRequestHandler<BroadcastFileChangeCommand>
{
    private readonly INotificationPusher _pusher;

    public BroadcastFileChangeCommandHandler(INotificationPusher pusher)
    {
        _pusher = pusher;
    }

    public async Task Handle(BroadcastFileChangeCommand request, CancellationToken cancellationToken)
    {
        var fileChange = new FileChangeDto(
            request.FileId,
            request.ChangeType,
            request.FileName,
            DateTime.UtcNow);

        // Send to all user's connected devices
        if (_pusher.IsUserConnected(request.UserId))
        {
            await _pusher.PushFileChangeAsync(request.UserId, fileChange, cancellationToken);
        }
    }
}
