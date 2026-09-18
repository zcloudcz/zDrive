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

    // True only for a shared (link-driven) upload session, minted from a
    // ShareUploadGrant rather than a JWT. Kept separate from "MaxBytes has a
    // value" so the authenticated and shared endpoint groups can refuse each
    // other's sessions outright (a Write-link grant for file F must not also
    // match the owner's own authenticated session on F, and vice versa) —
    // see UploadChunkCommandHandler/CompleteUploadCommandHandler/AbortUploadCommand.
    public bool IsShared { get; set; }

    // Only set for a shared upload, where the grant declares an upfront size
    // cap — an authenticated session has no such cap (quota is enforced
    // once, when FileService records the version).
    public long? MaxBytes { get; set; }

    // JSON-encoded {chunkIndex: bytesActuallyStored}, keyed per chunk index
    // rather than a running total: a client retrying one chunk (same index)
    // must replace its old size, not add to it, or a legitimate retry would
    // eventually 413 a correctly-sized upload. Read/written under
    // LockUploadSessionAsync's row lock so concurrent chunk PUTs of one
    // session can't race past MaxBytes together. "Bytes actually stored" —
    // never a client-declared size — because a chunked-transfer-encoding
    // request has no Content-Length to lie about in the first place.
    // ponytail: jsonb-as-text instead of a child table; a session has at
    // most a few hundred chunks, so this never gets large enough to need one.
    public string? ChunkSizesJson { get; set; }
}
