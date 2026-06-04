using Microsoft.AspNetCore.SignalR;
using ZDrive.NotificationService.Application.DTOs;
using ZDrive.NotificationService.Application.Interfaces;
using ZDrive.NotificationService.Domain.Entities;

namespace ZDrive.NotificationService.Infrastructure.SignalR;

public sealed class SignalRNotificationPusher : INotificationPusher
{
    private readonly IHubContext<SyncHub> _hubContext;
    private readonly ConnectionMapping _connectionMapping;

    public SignalRNotificationPusher(IHubContext<SyncHub> hubContext, ConnectionMapping connectionMapping)
    {
        _hubContext = hubContext;
        _connectionMapping = connectionMapping;
    }

    public async Task PushNotificationAsync(Guid userId, NotificationDto notification, CancellationToken ct = default)
    {
        var connectionIds = _connectionMapping.GetConnections(userId);
        if (connectionIds.Count == 0)
            return;

        await _hubContext.Clients
            .Clients(connectionIds)
            .SendAsync("ReceiveNotification", notification, ct);
    }

    public async Task PushFileChangeAsync(Guid userId, FileChangeDto fileChange, CancellationToken ct = default)
    {
        var connectionIds = _connectionMapping.GetConnections(userId);
        if (connectionIds.Count == 0)
            return;

        await _hubContext.Clients
            .Clients(connectionIds)
            .SendAsync("FileChanged", fileChange, ct);
    }

    public async Task PushSyncUpdateAsync(Guid userId, SyncUpdateDto syncUpdate, CancellationToken ct = default)
    {
        var connectionIds = _connectionMapping.GetConnections(userId);
        if (connectionIds.Count == 0)
            return;

        await _hubContext.Clients
            .Clients(connectionIds)
            .SendAsync("SyncUpdate", syncUpdate, ct);
    }

    public bool IsUserConnected(Guid userId) => _connectionMapping.IsConnected(userId);
}
