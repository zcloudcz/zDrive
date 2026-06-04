using Microsoft.EntityFrameworkCore;
using ZDrive.SyncService.Domain.Entities;

namespace ZDrive.SyncService.Application.Interfaces;

public interface ISyncDbContext
{
    DbSet<Device> Devices { get; }
    DbSet<SyncEvent> SyncEvents { get; }
    DbSet<SyncConflict> SyncConflicts { get; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
