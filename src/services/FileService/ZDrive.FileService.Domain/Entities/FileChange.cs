using ZDrive.FileService.Domain.Enums;

namespace ZDrive.FileService.Domain.Entities;

/// <summary>
/// Append-only log of FileNode mutations, written by FileChangeInterceptor in
/// the same SaveChanges call that makes the mutation. This is what lets every
/// client (desktop, web, mobile, BackupCli) that changes a file through
/// FileService produce a sync event, instead of only whichever client called
/// SyncService's push endpoint directly.
/// </summary>
public sealed class FileChange
{
    public long Id { get; set; }
    public Guid TenantId { get; set; }
    public Guid UserId { get; set; }
    public Guid FileId { get; set; }
    public FileChangeType Type { get; set; }
    public Guid? OriginDeviceId { get; set; }
    public DateTime OccurredAt { get; set; } = DateTime.UtcNow;
}
