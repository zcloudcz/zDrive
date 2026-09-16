using System.Data;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Domain.Entities;

namespace ZDrive.FileService.Infrastructure.Persistence;

public sealed class FileDbContext : DbContext, IFileDbContext
{
    public FileDbContext(DbContextOptions<FileDbContext> options) : base(options) { }

    public DbSet<FileNode> FileNodes => Set<FileNode>();
    public DbSet<FileVersion> FileVersions => Set<FileVersion>();
    public DbSet<Share> Shares => Set<Share>();
    public DbSet<FileChange> FileChanges => Set<FileChange>();

    public async Task<IAsyncDisposable> BeginFileChangeReadAsync(CancellationToken cancellationToken = default)
    {
        var transaction = await Database.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);
        try
        {
            // Inserts hold ROW EXCLUSIVE until commit. Wait for them and stop
            // new inserts allocating ids until the feed page is materialized.
            await Database.ExecuteSqlRawAsync("LOCK TABLE files.file_changes IN SHARE MODE", cancellationToken);
            return transaction;
        }
        catch
        {
            try
            {
                await transaction.RollbackAsync(CancellationToken.None);
            }
            finally
            {
                await transaction.DisposeAsync();
            }
            throw;
        }
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("files");
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(FileDbContext).Assembly);
    }
}
