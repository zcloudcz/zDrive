namespace ZDrive.FileService.Application.DTOs;

public sealed record FileChangeDto(long Id, Guid FileId, string Type, DateTime OccurredAt);

/// <summary>Cursor-paged slice of the change feed. NextCursor is the id of the last
/// returned change, or the request's own cursor when nothing was returned.</summary>
public sealed record FileChangesPageDto(List<FileChangeDto> Changes, long NextCursor, bool HasMore);
