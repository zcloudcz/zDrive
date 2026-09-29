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

    // Ingest pipeline state. (FileId, SourceManifestHash) is the idempotency
    // key: a new version of the file sets a new SourceManifestHash and queues
    // reprocessing; the same hash is a no-op.
    public string? SourceManifestHash { get; set; }
    public string? ProcessedManifestHash { get; set; }
    /// <summary>True while the file is trashed/deleted or is no longer an image.</summary>
    public bool IsHidden { get; set; }
    /// <summary>False for formats that cannot be decoded here (HEIC on Linux): metadata only.</summary>
    public bool ThumbnailsReady { get; set; }
    public int Attempts { get; set; }
    public string? FailureReason { get; set; }
    public DateTime? NextAttemptAt { get; set; }
    /// <summary>Processing lease: a claimed row is not re-claimed until this passes.</summary>
    public DateTime? LockedUntil { get; set; }
    public DateTime? ProcessedAt { get; set; }

    // Navigation
    public ICollection<PhotoTag> Tags { get; set; } = [];
    public ICollection<AlbumPhoto> AlbumPhotos { get; set; } = [];
}
