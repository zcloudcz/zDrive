using ZDrive.PhotoService.Domain.Enums;

namespace ZDrive.PhotoService.Domain.Entities;

public sealed class Album
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public Guid TenantId { get; set; }
    public required string Name { get; set; }
    public AlbumType Type { get; set; } = AlbumType.Manual;
    public Guid? CoverPhotoId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public ICollection<AlbumPhoto> AlbumPhotos { get; set; } = [];
}
