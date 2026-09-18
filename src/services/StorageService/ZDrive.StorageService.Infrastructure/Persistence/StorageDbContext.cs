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
    // Transaction-scoped: no matching unlock call needed, Postgres releases it
    // at commit/rollback. hashtext() on the two concatenated ids collapses
    // them into one bigint lock key per owner — collisions between different
    // owners are possible but harmless (worst case, unrelated owners briefly
    // serialize their init calls against each other).
    public async Task<IDbContextTransaction> LockOwnerSharedUploadBudgetAsync(
        Guid tenantId, Guid userId, CancellationToken cancellationToken)
    {
        var transaction = await Database.BeginTransactionAsync(cancellationToken);
        try
        {
            var key = $"{tenantId}:{userId}";
            await Database.ExecuteSqlInterpolatedAsync(
                $"SELECT pg_advisory_xact_lock(hashtext({key}))", cancellationToken);
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
