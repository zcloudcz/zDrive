using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.NotificationService.Application.Interfaces;

namespace ZDrive.NotificationService.Application.Commands.MarkAllRead;

public sealed class MarkAllReadCommandHandler : IRequestHandler<MarkAllReadCommand, int>
{
    private readonly INotificationDbContext _db;

    public MarkAllReadCommandHandler(INotificationDbContext db) => _db = db;

    public async Task<int> Handle(MarkAllReadCommand request, CancellationToken cancellationToken)
    {
        return await _db.Notifications
            .Where(n => n.UserId == request.UserId && !n.IsRead)
            .ExecuteUpdateAsync(
                s => s.SetProperty(n => n.IsRead, true),
                cancellationToken);
    }
}
