using MediatR;
using ZDrive.SyncService.Domain.Enums;

namespace ZDrive.SyncService.Application.Commands.ResolveConflict;

public sealed record ResolveConflictCommand(
    Guid UserId,
    Guid ConflictId,
    ConflictResolution Resolution) : IRequest<bool>;
