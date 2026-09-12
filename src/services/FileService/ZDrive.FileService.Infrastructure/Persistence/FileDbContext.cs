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

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("files");
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(FileDbContext).Assembly);
    }
}
