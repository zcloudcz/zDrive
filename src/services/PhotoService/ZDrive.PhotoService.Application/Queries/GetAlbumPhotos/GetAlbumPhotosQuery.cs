using MediatR;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.PhotoService.Application.Queries.GetAlbumPhotos;

public sealed record GetAlbumPhotosQuery(
    Guid UserId,
    Guid TenantId,
    Guid AlbumId,
    int Page = 1,
    int PageSize = 50) : IRequest<PagedResult<PhotoDto>>;
