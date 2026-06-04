namespace ZDrive.SyncService.Application.DTOs;

public sealed record SyncEventDto(
    long Id,
    Guid UserId,
    Guid DeviceId,
    Guid FileId,
    string EventType,
    string? Metadata,
    DateTime CreatedAt);
