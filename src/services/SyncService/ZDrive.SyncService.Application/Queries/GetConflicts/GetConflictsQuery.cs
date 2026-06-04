using MediatR;
using ZDrive.SyncService.Application.DTOs;

namespace ZDrive.SyncService.Application.Queries.GetConflicts;

public sealed record GetConflictsQuery(Guid UserId) : IRequest<List<SyncConflictDto>>;
