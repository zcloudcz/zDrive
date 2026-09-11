using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.FileService.Domain.Entities;

namespace ZDrive.FileService.Infrastructure.Persistence.Configurations;

public sealed class FileChangeConfiguration : IEntityTypeConfiguration<FileChange>
{
    public void Configure(EntityTypeBuilder<FileChange> builder)
    {
        builder.ToTable("file_changes");

        // long Id as an identity column (bigserial-equivalent) — Npgsql's EF
        // provider does this by convention for an integer key, no explicit
        // ValueGeneratedOnAdd needed.
        builder.HasKey(c => c.Id);

        builder.Property(c => c.Type)
            .HasConversion<string>()
            .HasMaxLength(20);

        builder.Property(c => c.OccurredAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        // Serves the feed query: WHERE tenant_id = ? AND user_id = ? AND id > cursor ORDER BY id.
        builder.HasIndex(c => new { c.TenantId, c.UserId, c.Id });
    }
}
