using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Commands.CreateFile;

public sealed record CreateFileCommand(
    Guid UserId,
    Guid TenantId,
    Guid? ParentId,
    string Name,
    bool IsFolder,
    long? SizeBytes,
    string? MimeType,
    string? BlobPath,
    string? ManifestHash) : IRequest<FileDto>;
