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

    // Only set for a shared (link-driven) upload, where the grant declares an
    // upfront size cap — an authenticated session has no such cap (quota is
    // enforced once, when FileService records the version). Tracked
    // cumulatively under LockUploadSessionAsync's row lock so concurrent
    // chunk PUTs of the same session can't each pass the check independently
    // and together blow past MaxBytes.
    public long? MaxBytes { get; set; }
    public long ReceivedBytes { get; set; }
}
