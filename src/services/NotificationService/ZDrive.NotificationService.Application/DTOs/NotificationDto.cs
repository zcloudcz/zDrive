namespace ZDrive.NotificationService.Application.DTOs;

public sealed record NotificationDto(
    Guid Id,
    Guid UserId,
    string Type,
    string Title,
    string Body,
    string? Data,
    bool IsRead,
    DateTime CreatedAt);
