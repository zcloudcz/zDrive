namespace ZDrive.BackupCli.Api;

/// <summary>
/// Mirrors the JSON shape returned by every service (camelCase, see
/// ZDrive.Shared.DTOs.ApiResponse&lt;T&gt; and its Program.cs camelCase policy).
/// </summary>
public sealed class ApiEnvelope<T>
{
    public bool Success { get; init; }
    public T? Data { get; init; }
    public ApiError? Error { get; init; }
}

public sealed class ApiError
{
    public string Code { get; init; } = string.Empty;
    public string Message { get; init; } = string.Empty;
}

public sealed record AuthTokens(string AccessToken, string RefreshToken, DateTime ExpiresAt);

public sealed record FileNode(
    Guid Id,
    string Name,
    bool IsFolder,
    long? SizeBytes,
    string? MimeType,
    Guid? ParentId,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    bool IsDeleted);

public sealed record PagedResult<T>(List<T> Items, int TotalCount, int Page, int PageSize);

public sealed record UploadSession(Guid SessionId, string SasUploadUrl);

public sealed record UploadComplete(string BlobPath, string ManifestHash, long TotalSize);

/// <summary>
/// The manifest StorageService writes to blob storage on upload completion.
/// Property names match ZDrive.StorageService.Domain.ValueObjects.ChunkManifest
/// exactly (PascalCase) — that JSON is written with the default
/// System.Text.Json options, not the API's camelCase policy.
/// </summary>
public sealed record RemoteManifest(Guid FileId, long TotalSize, List<RemoteChunk> Chunks);

public sealed record RemoteChunk(string Hash, int Index, long Size);

/// <summary>
/// A manifest fetched from blob storage, paired with the SHA-256 of its raw
/// bytes. That hash is, by construction, the same "manifestHash" StorageService
/// computed at CompleteUpload time and StorageService/FileService use to
/// identify the version — computing it from the downloaded bytes avoids
/// having to reproduce the server's JSON serialization exactly.
/// </summary>
public sealed record RemoteManifestResult(RemoteManifest Manifest, string ManifestHash);

/// <summary>Only the field BackupRunner needs from FileService's FileVersionDto.</summary>
public sealed record FileVersionSummary(string? ManifestHash);
