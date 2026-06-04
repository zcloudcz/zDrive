using ZDrive.StorageService.Domain.Enums;

namespace ZDrive.StorageService.Domain.Entities;

public sealed class UploadSession
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public Guid TenantId { get; set; }
    public Guid FileId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public UploadSessionStatus Status { get; set; } = UploadSessionStatus.Active;
    public int TotalChunks { get; set; }
    public int UploadedChunks { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime ExpiresAt { get; set; }
}
