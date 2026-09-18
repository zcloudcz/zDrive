namespace ZDrive.ApiGateway.Mcp;

// Minimal copies of the FileService/StorageService wire DTOs (see the contract
// at docs/superpowers/specs/2026-09-18-share-link-api-mcp-design.md). The
// gateway talks to those services over plain HTTP, not a project reference
// ("no special trust, no database access from the gateway"), so it needs its
// own shape to deserialize into — only the fields the tools actually use.

public sealed record FileDto(
    Guid Id,
    Guid? ParentId,
    string Name,
    bool IsFolder,
    long? SizeBytes,
    DateTime UpdatedAt);

public sealed record ShareQuotaDto(long LimitBytes, long UsedBytes);

public sealed record ShareInfoDto(
    string Permission,
    bool AllowDelete,
    DateTimeOffset? ExpiresAt,
    FileDto Root,
    ShareQuotaDto? Quota);

public sealed record ShareDownloadGrantDto(
    string Grant,
    DateTimeOffset ExpiresAt,
    Guid FileId,
    string FileName,
    long? SizeBytes,
    string ManifestHash);

public sealed record ManifestChunkDto(string Hash, int Index);

public sealed record ManifestDto(long TotalSize, List<ManifestChunkDto> Chunks, string? ManifestHash = null);

public sealed record ShareUploadGrantDto(
    string Grant,
    DateTimeOffset ExpiresAt,
    Guid FileId,
    string FileName,
    long MaxBytes);

public sealed record UploadSessionDto(Guid SessionId, string SasUploadUrl);

public sealed record ShareUploadCompleteDto(string ManifestHash, long TotalSize, string Receipt);
