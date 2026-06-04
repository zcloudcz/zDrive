using ZDrive.PhotoService.Domain.Enums;

namespace ZDrive.PhotoService.Domain.Entities;

public sealed class Photo
{
    public Guid Id { get; set; }
    public Guid FileId { get; set; }
    public Guid UserId { get; set; }
    public Guid TenantId { get; set; }
    public DateTime? TakenAt { get; set; }
    public double? Lat { get; set; }
    public double? Lng { get; set; }
    public string? CameraMake { get; set; }
    public string? CameraModel { get; set; }
    public int? Width { get; set; }
    public int? Height { get; set; }
    public int? Orientation { get; set; }
    public float? QualityScore { get; set; }
    public ProcessingStatus ProcessingStatus { get; set; } = ProcessingStatus.Pending;
    public required string OriginalFileName { get; set; }
    public required string BlobPath { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public ICollection<PhotoTag> Tags { get; set; } = [];
    public ICollection<AlbumPhoto> AlbumPhotos { get; set; } = [];
}
