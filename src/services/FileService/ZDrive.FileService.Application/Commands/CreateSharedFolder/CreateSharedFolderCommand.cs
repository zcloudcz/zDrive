using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Commands.CreateSharedFolder;

public sealed record CreateSharedFolderCommand(
    string LinkToken,
    Guid? ParentId,
    string Name) : IRequest<FileDto>;
