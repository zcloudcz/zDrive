namespace ZDrive.SyncService.Application.DTOs;

public sealed record PushResultDto(
    long NewCursor,
    List<SyncConflictDto> Conflicts);
