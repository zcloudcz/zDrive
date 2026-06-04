using Microsoft.EntityFrameworkCore;
using ZDrive.SyncService.Application.Interfaces;
using ZDrive.SyncService.Domain.Entities;

namespace ZDrive.SyncService.Infrastructure.Persistence;

public sealed class SyncDbContext : DbContext, ISyncDbContext
{
    public SyncDbContext(DbContextOptions<SyncDbContext> options) : base(options) { }

    public DbSet<Device> Devices => Set<Device>();
    public DbSet<SyncEvent> SyncEvents => Set<SyncEvent>();
    public DbSet<SyncConflict> SyncConflicts => Set<SyncConflict>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("sync");
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(SyncDbContext).Assembly);
    }
}
