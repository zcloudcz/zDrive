using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Domain.Entities;

namespace ZDrive.PhotoService.Application.Interfaces;

public interface IPhotoDbContext
{
    DbSet<Photo> Photos { get; }
    DbSet<PhotoTag> PhotoTags { get; }
    DbSet<Album> Albums { get; }
    DbSet<AlbumPhoto> AlbumPhotos { get; }
    DbSet<Memory> Memories { get; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
