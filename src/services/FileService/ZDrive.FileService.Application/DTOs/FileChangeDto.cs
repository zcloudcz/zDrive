namespace ZDrive.FileService.Application.DTOs;

public sealed record FileChangeDto(long Id, Guid FileId, string Type, DateTime OccurredAt);

/// <summary>Cursor-paged slice of the change feed. NextCursor is the id of the last
/// returned change, or the request's own cursor when nothing was returned.</summary>
public sealed record FileChangesPageDto(List<FileChangeDto> Changes, long NextCursor, bool HasMore);

/// <summary>One file touched by a page of the global feed, with its current state (null = node no longer exists).</summary>
public sealed record ChangedFileDto(Guid FileId, Guid TenantId, Guid UserId, FileSnapshotDto? Node);

public sealed record FileSnapshotDto(
    string Name, string? MimeType, bool IsFolder, bool IsDeleted, string? ManifestHash, DateTime CreatedAt);

public sealed record FileChangeBatchDto(List<ChangedFileDto> Files, long NextCursor, bool HasMore);
