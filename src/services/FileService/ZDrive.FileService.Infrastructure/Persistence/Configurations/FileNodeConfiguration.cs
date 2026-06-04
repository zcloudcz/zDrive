using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.FileService.Domain.Entities;

namespace ZDrive.FileService.Infrastructure.Persistence.Configurations;

public sealed class FileNodeConfiguration : IEntityTypeConfiguration<FileNode>
{
    public void Configure(EntityTypeBuilder<FileNode> builder)
    {
        builder.ToTable("file_nodes");

        builder.HasKey(f => f.Id);

        builder.Property(f => f.Name)
            .IsRequired()
            .HasMaxLength(512);

        builder.Property(f => f.MimeType)
            .HasMaxLength(256);

        builder.Property(f => f.BlobPath)
            .HasMaxLength(2048);

        builder.Property(f => f.ManifestHash)
            .HasMaxLength(128);

        builder.Property(f => f.CreatedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        builder.Property(f => f.UpdatedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        // Indexes
        builder.HasIndex(f => f.ParentId);

        builder.HasIndex(f => new { f.TenantId, f.UserId });

        builder.HasIndex(f => f.IsDeleted);

        builder.HasIndex(f => new { f.TenantId, f.UserId, f.ParentId, f.Name })
            .IsUnique()
            .HasFilter("is_deleted = false");

        // Self-referencing relationship
        builder.HasOne(f => f.Parent)
            .WithMany(f => f.Children)
            .HasForeignKey(f => f.ParentId)
            .OnDelete(DeleteBehavior.Restrict);

        // PostgreSQL full-text search: generated tsvector column on Name.
        // The column is created via raw SQL in the migration, but we configure
        // it as a shadow property so EF Core knows about it for queries.
        builder.Property<NpgsqlTypes.NpgsqlTsVector>("name_tsv")
            .HasColumnName("name_tsv")
            .IsRequired(false)
            .HasComputedColumnSql(@"to_tsvector('simple', ""Name"")", stored: true);

        builder.HasIndex("name_tsv")
            .HasMethod("GIN");
    }
}
