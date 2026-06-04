using ZDrive.FileService.Domain.Enums;

namespace ZDrive.FileService.Domain.Entities;

public sealed class Share
{
    public Guid Id { get; set; }
    public Guid FileId { get; set; }
    public Guid SharedBy { get; set; }
    public Guid? SharedWith { get; set; }
    public Permission Permission { get; set; }
    public required string LinkToken { get; set; }
    public string? PasswordHash { get; set; }
    public DateTime? ExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public bool IsExpired => ExpiresAt.HasValue && DateTime.UtcNow >= ExpiresAt.Value;

    // Navigation
    public FileNode File { get; set; } = null!;
}
