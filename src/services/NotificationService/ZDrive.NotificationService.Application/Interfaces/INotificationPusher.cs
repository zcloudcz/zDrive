using ZDrive.NotificationService.Application.DTOs;

namespace ZDrive.NotificationService.Application.Interfaces;

/// <summary>
/// Pushes real-time notifications to connected clients via SignalR.
/// </summary>
public interface INotificationPusher
{
    Task PushNotificationAsync(Guid userId, NotificationDto notification, CancellationToken ct = default);
    Task PushFileChangeAsync(Guid userId, FileChangeDto fileChange, CancellationToken ct = default);
    Task PushSyncUpdateAsync(Guid userId, SyncUpdateDto syncUpdate, CancellationToken ct = default);
    bool IsUserConnected(Guid userId);
}
