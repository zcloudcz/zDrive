using MediatR;
using ZDrive.PhotoService.Application.DTOs;

namespace ZDrive.PhotoService.Application.Queries.GetAlbums;

public sealed record GetAlbumsQuery(
    Guid UserId,
    Guid TenantId) : IRequest<List<AlbumDto>>;
