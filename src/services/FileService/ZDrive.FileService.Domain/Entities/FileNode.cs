namespace ZDrive.FileService.Domain.Entities;

public sealed class FileNode
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public Guid TenantId { get; set; }
    public Guid? ParentId { get; set; }
    public required string Name { get; set; }
    public bool IsFolder { get; set; }
    public long? SizeBytes { get; set; }
    public string? MimeType { get; set; }
    public string? BlobPath { get; set; }
    public string? ManifestHash { get; set; }
    public bool IsDeleted { get; set; }
    public DateTime? DeletedAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    // Navigation
    public FileNode? Parent { get; set; }
    public ICollection<FileNode> Children { get; set; } = [];
    public ICollection<Share> Shares { get; set; } = [];
    public ICollection<FileVersion> Versions { get; set; } = [];
}
