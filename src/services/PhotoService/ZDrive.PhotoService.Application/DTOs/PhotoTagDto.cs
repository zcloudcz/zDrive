namespace ZDrive.PhotoService.Application.DTOs;

public sealed record PhotoTagDto(
    Guid Id,
    Guid PhotoId,
    string Tag,
    float Confidence,
    string Source);
