using MediatR;

namespace ZDrive.NotificationService.Application.Commands.MarkAllRead;

public sealed record MarkAllReadCommand(Guid UserId) : IRequest<int>;
