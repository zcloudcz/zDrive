using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Queries.GetFile;

public sealed record GetFileQuery(
    Guid UserId,
    Guid TenantId,
    Guid FileId) : IRequest<FileDto>;
