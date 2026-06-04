using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Commands.RenameFile;

public sealed record RenameFileCommand(
    Guid UserId,
    Guid TenantId,
    Guid FileId,
    string NewName) : IRequest<FileDto>;
