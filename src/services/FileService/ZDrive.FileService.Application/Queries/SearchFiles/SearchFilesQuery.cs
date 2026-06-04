using MediatR;
using ZDrive.FileService.Application.DTOs;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Application.Queries.SearchFiles;

public sealed record SearchFilesQuery(
    Guid UserId,
    Guid TenantId,
    string Query,
    int Page = 1,
    int PageSize = 50) : IRequest<PagedResult<FileDto>>;
