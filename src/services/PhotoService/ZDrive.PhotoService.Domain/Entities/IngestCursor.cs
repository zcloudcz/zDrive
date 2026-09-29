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

    // One-time bootstrap from current file state (the change log starts empty,
    // ADR 0001, so files uploaded before it existed never appear in it).
    // BootstrapHead is the safe feed head captured BEFORE the node scan; the
    // cursor jumps to it when the scan completes. BootstrapLastNodeId is the
    // keyset position, so an interrupted scan resumes where it stopped.
    public long? BootstrapHead { get; set; }
    public Guid? BootstrapLastNodeId { get; set; }
    public DateTime? BootstrapCompletedAt { get; set; }
}
