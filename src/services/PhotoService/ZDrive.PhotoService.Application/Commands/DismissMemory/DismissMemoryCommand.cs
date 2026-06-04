using MediatR;

namespace ZDrive.PhotoService.Application.Commands.DismissMemory;

public sealed record DismissMemoryCommand(
    Guid UserId,
    Guid MemoryId) : IRequest<bool>;
