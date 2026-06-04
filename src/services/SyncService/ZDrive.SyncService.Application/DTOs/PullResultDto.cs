namespace ZDrive.SyncService.Application.DTOs;

public sealed record PullResultDto(
    List<SyncEventDto> Events,
    long NewCursor);
