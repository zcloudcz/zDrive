using MediatR;
using ZDrive.NotificationService.Application.DTOs;

namespace ZDrive.NotificationService.Application.Queries.GetPreferences;

public sealed record GetPreferencesQuery(Guid UserId) : IRequest<List<NotificationPreferenceDto>>;
