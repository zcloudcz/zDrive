using Microsoft.EntityFrameworkCore;
using ZDrive.NotificationService.Domain.Entities;

namespace ZDrive.NotificationService.Application.Interfaces;

public interface INotificationDbContext
{
    DbSet<Notification> Notifications { get; }
    DbSet<NotificationPreference> NotificationPreferences { get; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
