namespace ZDrive.PhotoService.Application.DTOs;

public sealed record AlbumDto(
    Guid Id,
    Guid UserId,
    Guid TenantId,
    string Name,
    string Type,
    Guid? CoverPhotoId,
    int PhotoCount,
    DateTime CreatedAt,
    DateTime UpdatedAt);
