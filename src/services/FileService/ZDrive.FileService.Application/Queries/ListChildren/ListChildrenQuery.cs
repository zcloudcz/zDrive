using MediatR;
using ZDrive.FileService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Application.Queries.ListChildren;

public sealed record ListChildrenQuery(
    Guid UserId,
    Guid TenantId,
    Guid? FolderId,
    int Page = 1,
    int PageSize = 50) : IRequest<PagedResult<FileDto>>;
