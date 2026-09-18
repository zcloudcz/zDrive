namespace ZDrive.FileService.Application.DTOs;

public sealed record ShareDto(
    Guid Id,
    Guid FileId,
    Guid SharedBy,
    Guid? SharedWith,
    string Permission,
    bool AllowDelete,
    string LinkToken,
    DateTime? ExpiresAt,
    DateTime CreatedAt);
