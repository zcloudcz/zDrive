using ZDrive.PhotoService.Domain.Enums;

namespace ZDrive.PhotoService.Domain.Entities;

public sealed class PhotoTag
{
    public Guid Id { get; set; }
    public Guid PhotoId { get; set; }
    public required string Tag { get; set; }
    public float Confidence { get; set; }
    public TagSource Source { get; set; }

    // Navigation
    public Photo? Photo { get; set; }
}
