namespace ZDrive.FileService.Application.DTOs;

public sealed record FileDto(
    Guid Id,
    Guid UserId,
    Guid TenantId,
    Guid? ParentId,
    string Name,
    bool IsFolder,
    long? SizeBytes,
    string? MimeType,
    string? BlobPath,
    string? ManifestHash,
    bool IsDeleted,
    DateTime? DeletedAt,
    DateTime CreatedAt,
    DateTime UpdatedAt);
