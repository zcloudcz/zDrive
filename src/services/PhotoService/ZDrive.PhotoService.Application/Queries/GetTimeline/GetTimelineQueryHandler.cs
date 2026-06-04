using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Application.Interfaces;

namespace ZDrive.PhotoService.Application.Queries.GetTimeline;

public sealed class GetTimelineQueryHandler : IRequestHandler<GetTimelineQuery, TimelineResultDto>
{
    private readonly IPhotoDbContext _db;

    public GetTimelineQueryHandler(IPhotoDbContext db) => _db = db;

    public async Task<TimelineResultDto> Handle(GetTimelineQuery request, CancellationToken cancellationToken)
    {
        var query = _db.Photos.AsNoTracking()
            .Where(p => p.UserId == request.UserId && p.TenantId == request.TenantId);

        if (request.From.HasValue)
        {
            var from = request.From.Value;
            query = query.Where(p => p.TakenAt >= from || (p.TakenAt == null && p.CreatedAt >= from));
        }

        if (request.To.HasValue)
        {
            var to = request.To.Value;
            query = query.Where(p => p.TakenAt <= to || (p.TakenAt == null && p.CreatedAt <= to));
        }

        var totalCount = await query.CountAsync(cancellationToken);

        // Order by TakenAt DESC (use CreatedAt as fallback when TakenAt is null)
        var photos = await query
            .OrderByDescending(p => p.TakenAt ?? p.CreatedAt)
            .Skip(request.Offset)
            .Take(request.Limit)
            .Select(p => p.ToDto())
            .ToListAsync(cancellationToken);

        return new TimelineResultDto(photos, totalCount);
    }
}
