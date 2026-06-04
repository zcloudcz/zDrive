using ZDrive.PhotoService.Domain.Enums;

namespace ZDrive.PhotoService.Domain.Entities;

public sealed class Memory
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public MemoryType Type { get; set; }
    public required string Title { get; set; }
    public DateTime DateFrom { get; set; }
    public DateTime DateTo { get; set; }
    public Guid[] PhotoIds { get; set; } = [];
    public bool Seen { get; set; }
    public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
}
