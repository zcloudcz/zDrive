using Microsoft.EntityFrameworkCore;
using ZDrive.StorageService.Application.Interfaces;
using ZDrive.StorageService.Domain.Entities;

namespace ZDrive.StorageService.Infrastructure.Persistence;

public sealed class StorageDbContext : DbContext, IStorageDbContext
{
    public StorageDbContext(DbContextOptions<StorageDbContext> options) : base(options) { }

    public DbSet<UploadSession> UploadSessions => Set<UploadSession>();
    public DbSet<BlobChunk> BlobChunks => Set<BlobChunk>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(StorageDbContext).Assembly);
    }
}
