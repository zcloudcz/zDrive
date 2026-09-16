using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using ZDrive.StorageService.Domain.Entities;

namespace ZDrive.StorageService.Application.Interfaces;

public interface IStorageDbContext
{
    DbSet<UploadSession> UploadSessions { get; }
    DbSet<BlobChunk> BlobChunks { get; }
    Task<IDbContextTransaction> LockUploadSessionAsync(Guid sessionId, CancellationToken cancellationToken);
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
