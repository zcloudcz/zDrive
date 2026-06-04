namespace ZDrive.NotificationService.Application.DTOs;

public sealed record FileChangeDto(
    Guid FileId,
    string ChangeType,
    string FileName,
    DateTime Timestamp);
