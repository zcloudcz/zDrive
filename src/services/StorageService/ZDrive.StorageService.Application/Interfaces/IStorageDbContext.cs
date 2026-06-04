using Microsoft.EntityFrameworkCore;
using ZDrive.StorageService.Domain.Entities;

namespace ZDrive.StorageService.Application.Interfaces;

public interface IStorageDbContext
{
    DbSet<UploadSession> UploadSessions { get; }
    DbSet<BlobChunk> BlobChunks { get; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
