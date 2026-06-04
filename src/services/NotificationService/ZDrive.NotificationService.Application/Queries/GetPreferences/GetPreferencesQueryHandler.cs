using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.NotificationService.Application.DTOs;
using ZDrive.NotificationService.Application.Interfaces;

namespace ZDrive.NotificationService.Application.Queries.GetPreferences;

public sealed class GetPreferencesQueryHandler : IRequestHandler<GetPreferencesQuery, List<NotificationPreferenceDto>>
{
    private readonly INotificationDbContext _db;

    public GetPreferencesQueryHandler(INotificationDbContext db) => _db = db;

    public async Task<List<NotificationPreferenceDto>> Handle(GetPreferencesQuery request, CancellationToken cancellationToken)
    {
        return await _db.NotificationPreferences
            .AsNoTracking()
            .Where(p => p.UserId == request.UserId)
            .OrderBy(p => p.Type)
            .ThenBy(p => p.Channel)
            .Select(p => new NotificationPreferenceDto(
                p.Id,
                p.UserId,
                p.Channel.ToString(),
                p.Type.ToString(),
                p.Enabled))
            .ToListAsync(cancellationToken);
    }
}
