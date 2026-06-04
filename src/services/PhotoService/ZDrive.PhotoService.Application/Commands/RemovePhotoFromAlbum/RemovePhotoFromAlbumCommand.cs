using MediatR;

namespace ZDrive.PhotoService.Application.Commands.RemovePhotoFromAlbum;

public sealed record RemovePhotoFromAlbumCommand(
    Guid UserId,
    Guid AlbumId,
    Guid PhotoId) : IRequest<bool>;
