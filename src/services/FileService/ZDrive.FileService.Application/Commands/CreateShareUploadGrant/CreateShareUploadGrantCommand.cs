using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Commands.CreateShareUploadGrant;

public sealed record CreateShareUploadGrantCommand(
    string LinkToken,
    Guid? ParentId,
    string? FileName,
    long SizeBytes,
    bool Overwrite) : IRequest<ShareUploadGrantResultDto>;
