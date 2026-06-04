using MediatR;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.PhotoService.Application.Queries.SearchPhotos;

public sealed record SearchPhotosQuery(
    Guid UserId,
    Guid TenantId,
    string Query,
    int Page = 1,
    int PageSize = 50) : IRequest<PagedResult<PhotoDto>>;
