using MediatR;
using ZDrive.SyncService.Application.DTOs;
using ZDrive.SyncService.Domain.Enums;

namespace ZDrive.SyncService.Application.Commands.PushChanges;

public sealed record PushChangesCommand(
    Guid UserId,
    Guid DeviceId,
    List<PushEventItem> Events) : IRequest<PushResultDto>;

public sealed record PushEventItem(
    Guid FileId,
    SyncEventType EventType,
    string? Metadata);
