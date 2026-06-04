using MediatR;

namespace ZDrive.FileService.Application.Commands.RevokeShare;

public sealed record RevokeShareCommand(
    Guid UserId,
    Guid ShareId) : IRequest<bool>;
