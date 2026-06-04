using ZDrive.SyncService.Domain.Enums;

namespace ZDrive.SyncService.Domain.Entities;

public sealed class SyncEvent
{
    public long Id { get; set; }
    public Guid UserId { get; set; }
    public Guid DeviceId { get; set; }
    public Guid FileId { get; set; }
    public SyncEventType EventType { get; set; }
    public string? Metadata { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
