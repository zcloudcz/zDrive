namespace ZDrive.FileService.Application.DTOs;

public sealed record ShareDownloadGrantDto(
    string Grant,
    DateTimeOffset ExpiresAt,
    Guid FileId,
    string FileName,
    long? SizeBytes,
    string ManifestHash);
