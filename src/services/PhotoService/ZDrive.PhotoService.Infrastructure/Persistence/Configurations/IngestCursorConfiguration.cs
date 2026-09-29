using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.PhotoService.Domain.Entities;

namespace ZDrive.PhotoService.Infrastructure.Persistence.Configurations;

public sealed class IngestCursorConfiguration : IEntityTypeConfiguration<IngestCursor>
{
    public void Configure(EntityTypeBuilder<IngestCursor> builder)
    {
        builder.ToTable("ingest_cursors");
        builder.HasKey(c => c.Name);
        builder.Property(c => c.Name).HasMaxLength(64);
    }
}
