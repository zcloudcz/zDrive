namespace ZDrive.NotificationService.Application.DTOs;

public sealed record SyncUpdateDto(
    string UpdateType,
    string Message,
    DateTime Timestamp);
