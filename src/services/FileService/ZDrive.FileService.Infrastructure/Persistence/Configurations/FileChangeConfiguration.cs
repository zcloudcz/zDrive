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

        // clock_timestamp() (not now()/transaction start) so a hot-open
        // transaction still gets a stamp close to the actual insert instant,
        // and one DB clock instead of each app instance's own clock rules
        // out clock skew between replicas — the feed's hold-back cutoff is
        // computed against this same clock (see GetFileChangesQueryHandler).
        builder.Property(c => c.OccurredAt)
            .HasDefaultValueSql("clock_timestamp()")
            .ValueGeneratedOnAdd();

        // Serves the feed query: WHERE tenant_id = ? AND user_id = ? AND id > cursor ORDER BY id.
        builder.HasIndex(c => new { c.TenantId, c.UserId, c.Id });
    }
}
