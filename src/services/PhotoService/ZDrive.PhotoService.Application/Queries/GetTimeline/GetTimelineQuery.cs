using MediatR;
using ZDrive.PhotoService.Application.DTOs;

namespace ZDrive.PhotoService.Application.Queries.GetTimeline;

public sealed record GetTimelineQuery(
    Guid UserId,
    Guid TenantId,
    DateTime? From,
    DateTime? To,
    int Limit = 50,
    int Offset = 0) : IRequest<TimelineResultDto>;
