using MediatR;

namespace ZDrive.PhotoService.Application.Commands.DeleteAlbum;

public sealed record DeleteAlbumCommand(
    Guid UserId,
    Guid AlbumId) : IRequest<bool>;
