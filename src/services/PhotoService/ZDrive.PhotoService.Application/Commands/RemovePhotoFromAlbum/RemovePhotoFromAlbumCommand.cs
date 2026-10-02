using MediatR;

namespace ZDrive.PhotoService.Application.Commands.RemovePhotoFromAlbum;

public sealed record RemovePhotoFromAlbumCommand(
    Guid UserId,
    Guid TenantId,
    Guid AlbumId,
    Guid PhotoId) : IRequest<bool>;
