using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.NotificationService.Application.DTOs;
using ZDrive.NotificationService.Application.Interfaces;
using ZDrive.NotificationService.Domain.Entities;

namespace ZDrive.NotificationService.Application.Commands.UpdatePreference;

public sealed class UpdatePreferenceCommandHandler : IRequestHandler<UpdatePreferenceCommand, NotificationPreferenceDto>
{
    private readonly INotificationDbContext _db;

    public UpdatePreferenceCommandHandler(INotificationDbContext db) => _db = db;

    public async Task<NotificationPreferenceDto> Handle(UpdatePreferenceCommand request, CancellationToken cancellationToken)
    {
        var preference = await _db.NotificationPreferences
            .FirstOrDefaultAsync(
                p => p.UserId == request.UserId
                     && p.Channel == request.Channel
                     && p.Type == request.Type,
                cancellationToken);

        if (preference is null)
        {
            preference = new NotificationPreference
            {
                Id = Guid.NewGuid(),
                UserId = request.UserId,
                Channel = request.Channel,
                Type = request.Type,
                Enabled = request.Enabled
            };
            _db.NotificationPreferences.Add(preference);
        }
        else
        {
            preference.Enabled = request.Enabled;
        }

        await _db.SaveChangesAsync(cancellationToken);

        return new NotificationPreferenceDto(
            preference.Id,
            preference.UserId,
            preference.Channel.ToString(),
            preference.Type.ToString(),
            preference.Enabled);
    }
}
