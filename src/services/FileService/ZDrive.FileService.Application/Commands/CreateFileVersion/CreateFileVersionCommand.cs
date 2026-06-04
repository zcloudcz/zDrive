using MediatR;
using ZDrive.FileService.Application.DTOs;

namespace ZDrive.FileService.Application.Commands.CreateFileVersion;

public sealed record CreateFileVersionCommand(
    Guid FileId,
    string BlobVersionId,
    long SizeBytes,
    string? ManifestHash,
    Guid CreatedBy,
    string? Comment) : IRequest<FileVersionDto>;
