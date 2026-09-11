using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Queries.GetFileChanges;

public sealed record GetFileChangesQuery(
    Guid UserId,
    Guid TenantId,
    long Cursor = 0,
    int Limit = 500,
    Guid? RequestingDeviceId = null) : IRequest<FileChangesPageDto>;
