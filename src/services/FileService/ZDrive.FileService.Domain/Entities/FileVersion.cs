namespace ZDrive.FileService.Domain.Entities;

public sealed class FileVersion
{
    public Guid Id { get; set; }
    public Guid FileId { get; set; }
    public int VersionNumber { get; set; }
    public required string BlobVersionId { get; set; }
    public long SizeBytes { get; set; }
    public string? ManifestHash { get; set; }
    public Guid CreatedBy { get; set; }
    public string? Comment { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public FileNode File { get; set; } = null!;
}
