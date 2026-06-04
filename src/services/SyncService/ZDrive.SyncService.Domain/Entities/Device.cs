using ZDrive.SyncService.Domain.Enums;

namespace ZDrive.SyncService.Domain.Entities;

public sealed class Device
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public required string Name { get; set; }
    public DevicePlatform Platform { get; set; }
    public long SyncCursor { get; set; }
    public DateTime? LastSyncAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
