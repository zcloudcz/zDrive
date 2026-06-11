using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Commands.CreateFileVersion;

public sealed record CreateFileVersionCommand(
    Guid TenantId,
    Guid UserId,
    Guid FileId,
    string BlobVersionId,
    long SizeBytes,
    string? ManifestHash,
    string? Comment) : IRequest<FileVersionDto>;
