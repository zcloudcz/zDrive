using ZDrive.SyncService.Domain.Enums;

namespace ZDrive.SyncService.Domain.Entities;

public sealed class SyncConflict
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public Guid FileId { get; set; }
    public Guid LocalDeviceId { get; set; }
    public Guid RemoteDeviceId { get; set; }
    public long LocalVersion { get; set; }
    public long RemoteVersion { get; set; }
    public ConflictStatus Status { get; set; } = ConflictStatus.Pending;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? ResolvedAt { get; set; }
}
