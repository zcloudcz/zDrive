using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;
using ZDrive.NotificationService.Domain.Entities;
using ZDrive.Shared.Auth;

namespace ZDrive.NotificationService.Infrastructure.SignalR;

[Authorize]
public sealed class SyncHub : Hub
{
    private readonly ConnectionMapping _connectionMapping;
    private readonly ILogger<SyncHub> _logger;

    public SyncHub(ConnectionMapping connectionMapping, ILogger<SyncHub> logger)
    {
        _connectionMapping = connectionMapping;
        _logger = logger;
    }

    public override Task OnConnectedAsync()
    {
        var userId = Context.User!.GetUserId();
        _connectionMapping.Add(userId, Context.ConnectionId);
        _logger.LogInformation("User {UserId} connected with connection {ConnectionId}", userId, Context.ConnectionId);
        return base.OnConnectedAsync();
    }

    public override Task OnDisconnectedAsync(Exception? exception)
    {
        var userId = Context.User!.GetUserId();
        _connectionMapping.Remove(userId, Context.ConnectionId);
        _logger.LogInformation("User {UserId} disconnected from connection {ConnectionId}", userId, Context.ConnectionId);
        return base.OnDisconnectedAsync(exception);
    }
}
