namespace ZDrive.SyncService.Application.DTOs;

public sealed record SyncConflictDto(
    Guid Id,
    Guid UserId,
    Guid FileId,
    Guid LocalDeviceId,
    Guid RemoteDeviceId,
    long LocalVersion,
    long RemoteVersion,
    string Status,
    DateTime CreatedAt,
    DateTime? ResolvedAt);
