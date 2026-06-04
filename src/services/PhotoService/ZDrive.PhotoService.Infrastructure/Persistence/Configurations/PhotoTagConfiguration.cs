using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.PhotoService.Domain.Entities;

namespace ZDrive.PhotoService.Infrastructure.Persistence.Configurations;

public sealed class PhotoTagConfiguration : IEntityTypeConfiguration<PhotoTag>
{
    public void Configure(EntityTypeBuilder<PhotoTag> builder)
    {
        builder.ToTable("photo_tags");

        builder.HasKey(t => t.Id);

        builder.Property(t => t.Tag)
            .IsRequired()
            .HasMaxLength(256);

        builder.Property(t => t.Source)
            .HasConversion<string>()
            .HasMaxLength(32);

        // GIN index on generated tsvector column for full-text search
        builder.Property<NpgsqlTypes.NpgsqlTsVector>("tag_tsv")
            .HasColumnName("tag_tsv")
            .IsRequired(false)
            .HasComputedColumnSql(@"to_tsvector('simple', ""Tag"")", stored: true);

        builder.HasIndex("tag_tsv")
            .HasMethod("GIN");

        builder.HasIndex(t => t.PhotoId);
    }
}
