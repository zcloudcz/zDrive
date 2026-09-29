using MediatR;
using ZDrive.PhotoService.Application.DTOs;

namespace ZDrive.PhotoService.Application.Commands.UpdateAlbum;

public sealed record UpdateAlbumCommand(
    Guid UserId,
    Guid TenantId,
    Guid AlbumId,
    string? Name,
    Guid? CoverPhotoId) : IRequest<AlbumDto>;
