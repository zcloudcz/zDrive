using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Queries.GetFileVersions;

public sealed record GetFileVersionsQuery(
    Guid UserId,
    Guid TenantId,
    Guid FileId) : IRequest<List<FileVersionDto>>;
