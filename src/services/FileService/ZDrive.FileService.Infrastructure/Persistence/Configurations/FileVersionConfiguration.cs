using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.FileService.Domain.Entities;

namespace ZDrive.FileService.Infrastructure.Persistence.Configurations;

public sealed class FileVersionConfiguration : IEntityTypeConfiguration<FileVersion>
{
    public void Configure(EntityTypeBuilder<FileVersion> builder)
    {
        builder.ToTable("file_versions");

        builder.HasKey(v => v.Id);

        builder.Property(v => v.BlobVersionId)
            .IsRequired()
            .HasMaxLength(512);

        builder.Property(v => v.ManifestHash)
            .HasMaxLength(128);

        builder.Property(v => v.Comment)
            .HasMaxLength(1024);

        builder.Property(v => v.CreatedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        builder.HasIndex(v => new { v.FileId, v.VersionNumber })
            .IsUnique();

        builder.HasOne(v => v.File)
            .WithMany(f => f.Versions)
            .HasForeignKey(v => v.FileId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
