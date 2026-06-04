using MediatR;
using ZDrive.FileService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Application.Queries.ListTrash;

public sealed record ListTrashQuery(
    Guid UserId,
    Guid TenantId,
    int Page = 1,
    int PageSize = 50) : IRequest<PagedResult<FileDto>>;
