using MediatR;
using ZDrive.NotificationService.Application.DTOs;
using ZDrive.NotificationService.Application.Interfaces;
using ZDrive.NotificationService.Domain.Entities;

namespace ZDrive.NotificationService.Application.Commands.SendNotification;

public sealed class SendNotificationCommandHandler : IRequestHandler<SendNotificationCommand, NotificationDto>
{
    private readonly INotificationDbContext _db;
    private readonly INotificationPusher _pusher;

    public SendNotificationCommandHandler(INotificationDbContext db, INotificationPusher pusher)
    {
        _db = db;
        _pusher = pusher;
    }

    public async Task<NotificationDto> Handle(SendNotificationCommand request, CancellationToken cancellationToken)
    {
        var notification = new Notification
        {
            Id = Guid.NewGuid(),
            UserId = request.UserId,
            Type = request.Type,
            Title = request.Title,
            Body = request.Body,
            Data = request.Data,
            IsRead = false
        };

        _db.Notifications.Add(notification);
        await _db.SaveChangesAsync(cancellationToken);

        var dto = new NotificationDto(
            notification.Id,
            notification.UserId,
            notification.Type.ToString(),
            notification.Title,
            notification.Body,
            notification.Data,
            notification.IsRead,
            notification.CreatedAt);

        // Push via SignalR if user is connected
        if (_pusher.IsUserConnected(request.UserId))
        {
            await _pusher.PushNotificationAsync(request.UserId, dto, cancellationToken);
        }

        return dto;
    }
}
