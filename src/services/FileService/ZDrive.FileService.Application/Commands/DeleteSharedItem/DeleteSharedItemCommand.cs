using MediatR;

namespace ZDrive.FileService.Application.Commands.DeleteSharedItem;

public sealed record DeleteSharedItemCommand(string LinkToken, Guid ItemId) : IRequest<bool>;
