namespace ZDrive.PhotoService.Application.DTOs;

public sealed record PhotoDto(
    Guid Id,
    Guid FileId,
    Guid UserId,
    Guid TenantId,
    DateTime? TakenAt,
    double? Lat,
    double? Lng,
    string? CameraMake,
    string? CameraModel,
    int? Width,
    int? Height,
    int? Orientation,
    float? QualityScore,
    string ProcessingStatus,
    string OriginalFileName,
    string BlobPath,
    DateTime CreatedAt,
    bool ThumbnailsReady);
