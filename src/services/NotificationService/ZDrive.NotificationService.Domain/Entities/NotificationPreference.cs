using ZDrive.NotificationService.Domain.Enums;

namespace ZDrive.NotificationService.Domain.Entities;

public sealed class NotificationPreference
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public NotificationChannel Channel { get; set; }
    public NotificationType Type { get; set; }
    public bool Enabled { get; set; } = true;
}
