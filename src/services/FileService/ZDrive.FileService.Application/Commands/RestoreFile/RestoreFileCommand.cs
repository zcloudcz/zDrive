using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Commands.RestoreFile;

public sealed record RestoreFileCommand(
    Guid UserId,
    Guid TenantId,
    Guid FileId) : IRequest<FileDto>;
