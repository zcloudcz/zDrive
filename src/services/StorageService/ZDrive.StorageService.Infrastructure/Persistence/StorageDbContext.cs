using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Domain.Entities;

namespace ZDrive.StorageService.Infrastructure.Persistence;

public sealed class StorageDbContext : DbContext, IStorageDbContext
{
    public StorageDbContext(DbContextOptions<StorageDbContext> options) : base(options) { }

    public DbSet<UploadSession> UploadSessions => Set<UploadSession>();
    public DbSet<BlobChunk> BlobChunks => Set<BlobChunk>();

    // Hold the session row through blob I/O so abort cannot race a late chunk write.
    public async Task<IDbContextTransaction> LockUploadSessionAsync(Guid sessionId, CancellationToken cancellationToken)
    {
        var transaction = await Database.BeginTransactionAsync(cancellationToken);
        try
        {
            await Database.ExecuteSqlInterpolatedAsync(
                $"SELECT 1 FROM storage.upload_sessions WHERE \"Id\" = {sessionId} FOR UPDATE", cancellationToken);
            return transaction;
        }
        catch
        {
            await transaction.DisposeAsync();
            throw;
        }
    }
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("storage");
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(StorageDbContext).Assembly);
    }
}
