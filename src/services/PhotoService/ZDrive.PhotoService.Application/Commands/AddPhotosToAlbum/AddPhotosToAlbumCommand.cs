using MediatR;

namespace ZDrive.PhotoService.Application.Commands.AddPhotosToAlbum;

public sealed record AddPhotosToAlbumCommand(
    Guid UserId,
    Guid AlbumId,
    Guid[] PhotoIds) : IRequest<int>;
