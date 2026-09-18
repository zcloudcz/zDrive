using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.StorageService.Domain.Entities;

namespace ZDrive.StorageService.Infrastructure.Persistence.Configurations;

public sealed class UploadSessionConfiguration : IEntityTypeConfiguration<UploadSession>
{
    public void Configure(EntityTypeBuilder<UploadSession> builder)
    {
        builder.ToTable("upload_sessions");

        builder.HasKey(x => x.Id);

        builder.Property(x => x.UserId).IsRequired();
        builder.Property(x => x.TenantId).IsRequired();
        builder.Property(x => x.FileId).IsRequired();
        builder.Property(x => x.FileName).IsRequired().HasMaxLength(1024);
        builder.Property(x => x.Status).IsRequired();
        builder.Property(x => x.TotalChunks).IsRequired();
        builder.Property(x => x.UploadedChunks).IsRequired();
        builder.Property(x => x.CreatedAt).IsRequired();
        builder.Property(x => x.ExpiresAt).IsRequired();
        builder.Property(x => x.IsShared).IsRequired().HasDefaultValue(false);
        builder.Property(x => x.ChunkSizesJson).HasColumnType("text");

        builder.HasIndex(x => x.FileId);
        builder.HasIndex(x => new { x.TenantId, x.UserId });

        // Backs the shared-session 24h in-flight budget check in
        // InitUploadCommandHandler (SUM(MaxBytes) over this owner's open
        // shared sessions from the last day).
        builder.HasIndex(x => new { x.TenantId, x.UserId, x.IsShared, x.CreatedAt });
    }
}
