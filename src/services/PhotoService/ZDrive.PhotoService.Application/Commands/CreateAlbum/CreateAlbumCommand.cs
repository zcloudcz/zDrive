using MediatR;
using ZDrive.PhotoService.Application.DTOs;

namespace ZDrive.PhotoService.Application.Commands.CreateAlbum;

public sealed record CreateAlbumCommand(
    Guid UserId,
    Guid TenantId,
    string Name) : IRequest<AlbumDto>;
