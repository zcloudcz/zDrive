namespace ZDrive.NotificationService.Application.DTOs;

public sealed record NotificationPreferenceDto(
    Guid Id,
    Guid UserId,
    string Channel,
    string Type,
    bool Enabled);
