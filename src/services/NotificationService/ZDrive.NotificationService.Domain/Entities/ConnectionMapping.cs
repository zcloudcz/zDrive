using System.Collections.Concurrent;

namespace ZDrive.NotificationService.Domain.Entities;

/// <summary>
/// Thread-safe in-memory mapping of userId to SignalR connectionIds.
/// A single user can have multiple connected devices.
/// </summary>
public sealed class ConnectionMapping
{
    private readonly ConcurrentDictionary<Guid, HashSet<string>> _connections = new();
    private readonly object _lock = new();

    public void Add(Guid userId, string connectionId)
    {
        _connections.AddOrUpdate(
            userId,
            _ => [connectionId],
            (_, existing) =>
            {
                lock (_lock)
                {
                    existing.Add(connectionId);
                    return existing;
                }
            });
    }

    public void Remove(Guid userId, string connectionId)
    {
        if (!_connections.TryGetValue(userId, out var connections))
            return;

        lock (_lock)
        {
            connections.Remove(connectionId);
            if (connections.Count == 0)
                _connections.TryRemove(userId, out _);
        }
    }

    public IReadOnlyList<string> GetConnections(Guid userId)
    {
        if (_connections.TryGetValue(userId, out var connections))
        {
            lock (_lock)
            {
                return connections.ToList();
            }
        }

        return [];
    }

    public bool IsConnected(Guid userId) => _connections.ContainsKey(userId);

    public int ConnectionCount
    {
        get
        {
            lock (_lock)
            {
                return _connections.Values.Sum(c => c.Count);
            }
        }
    }
}
