using MediatR;

namespace ZDrive.NotificationService.Application.Commands.BroadcastFileChange;

public sealed record BroadcastFileChangeCommand(
    Guid UserId,
    Guid FileId,
    string ChangeType,
    string FileName) : IRequest;
