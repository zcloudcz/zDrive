namespace ZDrive.FileService.Application.DTOs;

public sealed record ShareUploadGrantResultDto(
    string Grant,
    DateTimeOffset ExpiresAt,
    Guid FileId,
    string FileName,
    long MaxBytes);
