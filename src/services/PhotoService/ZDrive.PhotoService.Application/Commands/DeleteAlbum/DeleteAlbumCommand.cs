using MediatR;

namespace ZDrive.PhotoService.Application.Commands.DeleteAlbum;

public sealed record DeleteAlbumCommand(
    Guid UserId,
    Guid TenantId,
    Guid AlbumId) : IRequest<bool>;
