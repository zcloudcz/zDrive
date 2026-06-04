using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.SyncService.Domain.Entities;

namespace ZDrive.SyncService.Infrastructure.Persistence.Configurations;

public sealed class SyncEventConfiguration : IEntityTypeConfiguration<SyncEvent>
{
    public void Configure(EntityTypeBuilder<SyncEvent> builder)
    {
        builder.ToTable("sync_events");

        builder.HasKey(e => e.Id);

        // bigint auto-increment via sequence for ordered IDs.
        builder.Property(e => e.Id)
            .UseHiLo("sync_event_id_seq", "sync");

        builder.Property(e => e.EventType)
            .HasConversion<string>()
            .HasMaxLength(20);

        builder.Property(e => e.Metadata)
            .HasColumnType("jsonb");

        builder.Property(e => e.CreatedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        // Primary cursor query: fetch events for a user after a given ID.
        builder.HasIndex(e => new { e.UserId, e.Id });

        builder.HasIndex(e => e.DeviceId);

        builder.HasIndex(e => e.FileId);
    }
}
