namespace ZDrive.PhotoService.Domain.Entities;

/// <summary>
/// Durable position of the ingest worker in FileService's global change feed
/// (one row per feed; today only <see cref="FileChangesName"/>).
/// </summary>
public sealed class IngestCursor
{
    public const string FileChangesName = "file-changes";

    public required string Name { get; set; }
    public long LastChangeId { get; set; }
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
