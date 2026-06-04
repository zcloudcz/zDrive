using MediatR;
using ZDrive.NotificationService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.NotificationService.Application.Queries.GetNotifications;

public sealed record GetNotificationsQuery(
    Guid UserId,
    int Page = 1,
    int PageSize = 20,
    bool? UnreadOnly = null) : IRequest<PagedResult<NotificationDto>>;
