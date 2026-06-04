using MediatR;

namespace ZDrive.FileService.Application.Commands.DeleteFile;

public sealed record DeleteFileCommand(
    Guid UserId,
    Guid TenantId,
    Guid FileId) : IRequest<bool>;
