using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.PhotoService.Domain.Entities;

namespace ZDrive.PhotoService.Infrastructure.Persistence.Configurations;

public sealed class PhotoConfiguration : IEntityTypeConfiguration<Photo>
{
    public void Configure(EntityTypeBuilder<Photo> builder)
    {
        builder.ToTable("photos");

        builder.HasKey(p => p.Id);

        builder.Property(p => p.OriginalFileName)
            .IsRequired()
            .HasMaxLength(1024);

        builder.Property(p => p.BlobPath)
            .IsRequired()
            .HasMaxLength(2048);

        builder.Property(p => p.CameraMake)
            .HasMaxLength(256);

        builder.Property(p => p.CameraModel)
            .HasMaxLength(256);

        builder.Property(p => p.ProcessingStatus)
            .HasConversion<string>()
            .HasMaxLength(32);

        builder.Property(p => p.CreatedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        builder.Property(p => p.SourceManifestHash).HasMaxLength(128);
        builder.Property(p => p.ProcessedManifestHash).HasMaxLength(128);
        builder.Property(p => p.FailureReason).HasMaxLength(1024);

        // Trashed / non-image photos are invisible to every read. The ingest
        // worker is the only caller that uses IgnoreQueryFilters().
        builder.HasQueryFilter(p => !p.IsHidden);

        // Serves the worker's claim query.
        builder.HasIndex(p => new { p.ProcessingStatus, p.NextAttemptAt });

        // Indexes
        builder.HasIndex(p => new { p.UserId, p.TakenAt });
        builder.HasIndex(p => new { p.TenantId, p.UserId });
        builder.HasIndex(p => p.FileId).IsUnique();

        // Navigation to tags
        builder.HasMany(p => p.Tags)
            .WithOne(t => t.Photo)
            .HasForeignKey(t => t.PhotoId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
