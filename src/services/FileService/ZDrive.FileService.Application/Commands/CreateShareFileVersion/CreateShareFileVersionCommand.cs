using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Commands.CreateShareFileVersion;

public sealed record CreateShareFileVersionCommand(
    string LinkToken,
    Guid FileId,
    string Receipt) : IRequest<FileDto>;
