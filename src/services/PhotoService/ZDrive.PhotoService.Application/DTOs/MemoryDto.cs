namespace ZDrive.PhotoService.Application.DTOs;

public sealed record MemoryDto(
    Guid Id,
    Guid UserId,
    string Type,
    string Title,
    DateTime DateFrom,
    DateTime DateTo,
    Guid[] PhotoIds,
    bool Seen,
    DateTime GeneratedAt);
