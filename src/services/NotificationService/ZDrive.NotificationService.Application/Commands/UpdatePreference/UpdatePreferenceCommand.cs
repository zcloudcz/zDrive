using MediatR;
using ZDrive.NotificationService.Application.DTOs;
using ZDrive.NotificationService.Domain.Enums;

namespace ZDrive.NotificationService.Application.Commands.UpdatePreference;

public sealed record UpdatePreferenceCommand(
    Guid UserId,
    NotificationChannel Channel,
    NotificationType Type,
    bool Enabled) : IRequest<NotificationPreferenceDto>;
