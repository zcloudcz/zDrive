using MediatR;

namespace ZDrive.NotificationService.Application.Commands.MarkRead;

public sealed record MarkReadCommand(
    Guid UserId,
    Guid NotificationId) : IRequest<bool>;
