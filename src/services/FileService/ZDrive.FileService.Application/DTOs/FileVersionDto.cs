namespace ZDrive.FileService.Application.DTOs;

public sealed record FileVersionDto(
    Guid Id,
    Guid FileId,
    int VersionNumber,
    string BlobVersionId,
    long SizeBytes,
    string? ManifestHash,
    Guid CreatedBy,
    string? Comment,
    DateTime CreatedAt);
