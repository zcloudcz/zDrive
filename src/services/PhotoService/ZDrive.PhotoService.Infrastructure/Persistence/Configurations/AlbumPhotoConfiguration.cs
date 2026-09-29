using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.PhotoService.Domain.Entities;

namespace ZDrive.PhotoService.Infrastructure.Persistence.Configurations;

public sealed class AlbumPhotoConfiguration : IEntityTypeConfiguration<AlbumPhoto>
{
    public void Configure(EntityTypeBuilder<AlbumPhoto> builder)
    {
        builder.ToTable("album_photos");

        // Composite primary key
        builder.HasKey(ap => new { ap.AlbumId, ap.PhotoId });

        builder.Property(ap => ap.AddedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        // Matches the Photo query filter (hidden photos vanish from albums and counts).
        builder.HasQueryFilter(ap => !ap.Photo!.IsHidden);

        builder.HasOne(ap => ap.Album)
            .WithMany(a => a.AlbumPhotos)
            .HasForeignKey(ap => ap.AlbumId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(ap => ap.Photo)
            .WithMany(p => p.AlbumPhotos)
            .HasForeignKey(ap => ap.PhotoId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
