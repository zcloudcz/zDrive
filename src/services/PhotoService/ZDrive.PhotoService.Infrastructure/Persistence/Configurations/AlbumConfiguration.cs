using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.PhotoService.Domain.Entities;

namespace ZDrive.PhotoService.Infrastructure.Persistence.Configurations;

public sealed class AlbumConfiguration : IEntityTypeConfiguration<Album>
{
    public void Configure(EntityTypeBuilder<Album> builder)
    {
        builder.ToTable("albums");

        builder.HasKey(a => a.Id);

        builder.Property(a => a.Name)
            .IsRequired()
            .HasMaxLength(256);

        builder.Property(a => a.Type)
            .HasConversion<string>()
            .HasMaxLength(32);

        builder.Property(a => a.CreatedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        builder.Property(a => a.UpdatedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        // Indexes
        builder.HasIndex(a => new { a.UserId, a.TenantId });
    }
}
