using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.FileService.Domain.Entities;

namespace ZDrive.FileService.Infrastructure.Persistence.Configurations;

public sealed class ShareConfiguration : IEntityTypeConfiguration<Share>
{
    public void Configure(EntityTypeBuilder<Share> builder)
    {
        builder.ToTable("shares");

        builder.HasKey(s => s.Id);

        builder.Property(s => s.LinkToken)
            .IsRequired()
            .HasMaxLength(256);

        builder.HasIndex(s => s.LinkToken)
            .IsUnique();

        builder.Property(s => s.PasswordHash)
            .HasMaxLength(512);

        builder.Property(s => s.Permission)
            .HasConversion<string>()
            .HasMaxLength(20);

        builder.Property(s => s.CreatedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        builder.HasIndex(s => s.FileId);

        builder.HasOne(s => s.File)
            .WithMany(f => f.Shares)
            .HasForeignKey(s => s.FileId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
