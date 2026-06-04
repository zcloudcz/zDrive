using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.PhotoService.Domain.Entities;

namespace ZDrive.PhotoService.Infrastructure.Persistence.Configurations;

public sealed class MemoryConfiguration : IEntityTypeConfiguration<Memory>
{
    public void Configure(EntityTypeBuilder<Memory> builder)
    {
        builder.ToTable("memories");

        builder.HasKey(m => m.Id);

        builder.Property(m => m.Title)
            .IsRequired()
            .HasMaxLength(512);

        builder.Property(m => m.Type)
            .HasConversion<string>()
            .HasMaxLength(32);

        builder.Property(m => m.GeneratedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        // Indexes
        builder.HasIndex(m => new { m.UserId, m.GeneratedAt });
    }
}
