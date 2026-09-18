namespace ZDrive.FileService.Application.DTOs;

/// <summary>Quota numbers for the share owner — null when package B's IStorageQuota isn't wired up.</summary>
public sealed record ShareQuotaDto(long LimitBytes, long UsedBytes);

public sealed record ShareInfoDto(
    string Permission,
    bool AllowDelete,
    DateTime? ExpiresAt,
    FileDto Root,
    ShareQuotaDto? Quota);
