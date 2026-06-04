using MediatR;
using ZDrive.SyncService.Application.DTOs;

namespace ZDrive.SyncService.Application.Queries.PullChanges;

public sealed record PullChangesQuery(
    Guid UserId,
    Guid DeviceId,
    long Cursor) : IRequest<PullResultDto>;
