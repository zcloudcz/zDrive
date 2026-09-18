using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using ZDrive.StorageService.Domain.Entities;

namespace ZDrive.StorageService.Application.Interfaces;

public interface IStorageDbContext
{
    DbSet<UploadSession> UploadSessions { get; }
    DbSet<BlobChunk> BlobChunks { get; }
    Task<IDbContextTransaction> LockUploadSessionAsync(Guid sessionId, CancellationToken cancellationToken);

    /// <summary>
    /// Transaction-scoped advisory lock (pg_advisory_xact_lock — auto-released
    /// at commit/rollback, unlike LockUploadSessionAsync's row lock which
    /// needs no unlock call either but locks an existing row rather than a
    /// key) keyed on (tenantId, userId), for serializing the shared-upload
    /// 24h in-flight budget check-and-insert in InitUploadCommandHandler:
    /// without it, two concurrent inits for the same owner can both read the
    /// same SUM before either's insert is visible, so both pass a check
    /// that only one of them should have.
    /// </summary>
    Task<IDbContextTransaction> LockOwnerSharedUploadBudgetAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken);

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
