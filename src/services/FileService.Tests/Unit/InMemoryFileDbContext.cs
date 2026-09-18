using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Domain.Entities;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// A plain EF Core InMemory-backed IFileDbContext for handler-level unit
/// tests that don't need real Postgres behaviour (computed columns, GIN
/// indexes, etc. — see FileDbContext's own OnModelCreating, which is
/// Postgres-specific and doesn't run under InMemory). This lets handlers
/// like ListSharedChildrenQueryHandler and CreateShareDownloadGrantCommandHandler
/// be exercised without Docker, unlike the *FlowTests integration suites.
/// </summary>
public sealed class InMemoryFileDbContext : DbContext, IFileDbContext
{
    public InMemoryFileDbContext(DbContextOptions<InMemoryFileDbContext> options) : base(options) { }

    public DbSet<FileNode> FileNodes => Set<FileNode>();
    public DbSet<FileVersion> FileVersions => Set<FileVersion>();
    public DbSet<Share> Shares => Set<Share>();
    public DbSet<FileChange> FileChanges => Set<FileChange>();

    // Not exercised by any handler under test here (it backs the sync change
    // feed, unrelated to public shares).
    public Task<IAsyncDisposable> BeginFileChangeReadAsync(CancellationToken cancellationToken = default) =>
        throw new NotSupportedException("Not used by the handlers under test.");

    public static InMemoryFileDbContext Create()
    {
        var options = new DbContextOptionsBuilder<InMemoryFileDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        return new InMemoryFileDbContext(options);
    }
}
