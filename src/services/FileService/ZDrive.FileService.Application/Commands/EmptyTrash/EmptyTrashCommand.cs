using MediatR;

namespace ZDrive.FileService.Application.Commands.EmptyTrash;

public sealed record EmptyTrashCommand(
    Guid UserId,
    Guid TenantId) : IRequest<int>;
