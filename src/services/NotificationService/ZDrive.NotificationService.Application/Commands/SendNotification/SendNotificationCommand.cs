using MediatR;
using ZDrive.NotificationService.Application.DTOs;
using ZDrive.NotificationService.Domain.Enums;

namespace ZDrive.NotificationService.Application.Commands.SendNotification;

public sealed record SendNotificationCommand(
    Guid UserId,
    NotificationType Type,
    string Title,
    string Body,
    string? Data = null) : IRequest<NotificationDto>;
