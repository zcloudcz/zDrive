namespace ZDrive.SyncService.Application.DTOs;

public sealed record DeviceDto(
    Guid Id,
    Guid UserId,
    string Name,
    string Platform,
    long SyncCursor,
    DateTime? LastSyncAt,
    DateTime CreatedAt);
