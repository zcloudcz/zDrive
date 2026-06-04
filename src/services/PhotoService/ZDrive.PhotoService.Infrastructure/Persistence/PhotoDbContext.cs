using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.PhotoService.Domain.Entities;

namespace ZDrive.PhotoService.Infrastructure.Persistence;

public sealed class PhotoDbContext : DbContext, IPhotoDbContext
{
    public PhotoDbContext(DbContextOptions<PhotoDbContext> options) : base(options) { }

    public DbSet<Photo> Photos => Set<Photo>();
    public DbSet<PhotoTag> PhotoTags => Set<PhotoTag>();
    public DbSet<Album> Albums => Set<Album>();
    public DbSet<AlbumPhoto> AlbumPhotos => Set<AlbumPhoto>();
    public DbSet<Memory> Memories => Set<Memory>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("photos");
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(PhotoDbContext).Assembly);
    }
}
