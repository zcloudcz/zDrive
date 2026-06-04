using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.NotificationService.Application.Interfaces;

namespace ZDrive.NotificationService.Application.Commands.MarkRead;

public sealed class MarkReadCommandHandler : IRequestHandler<MarkReadCommand, bool>
{
    private readonly INotificationDbContext _db;

    public MarkReadCommandHandler(INotificationDbContext db) => _db = db;

    public async Task<bool> Handle(MarkReadCommand request, CancellationToken cancellationToken)
    {
        var notification = await _db.Notifications
            .FirstOrDefaultAsync(
                n => n.Id == request.NotificationId && n.UserId == request.UserId,
                cancellationToken);

        if (notification is null)
            return false;

        if (notification.IsRead)
            return true;

        notification.IsRead = true;
        await _db.SaveChangesAsync(cancellationToken);
        return true;
    }
}
