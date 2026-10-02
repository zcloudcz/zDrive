using MediatR;

namespace ZDrive.PhotoService.Application.Commands.AddPhotosToAlbum;

public sealed record AddPhotosToAlbumCommand(
    Guid UserId,
    Guid TenantId,
    Guid AlbumId,
    Guid[] PhotoIds) : IRequest<int>;
