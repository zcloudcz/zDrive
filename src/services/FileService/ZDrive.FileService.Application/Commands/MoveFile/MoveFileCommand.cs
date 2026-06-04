using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Commands.MoveFile;

public sealed record MoveFileCommand(
    Guid UserId,
    Guid TenantId,
    Guid FileId,
    Guid? NewParentId) : IRequest<FileDto>;
