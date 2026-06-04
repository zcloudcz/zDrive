namespace ZDrive.FileService.Application.DTOs;

public sealed record ShareDto(
    Guid Id,
    Guid FileId,
    Guid SharedBy,
    Guid? SharedWith,
    string Permission,
    string LinkToken,
    DateTime? ExpiresAt,
    DateTime CreatedAt);
