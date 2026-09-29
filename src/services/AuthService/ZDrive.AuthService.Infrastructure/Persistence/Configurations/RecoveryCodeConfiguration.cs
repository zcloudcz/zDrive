using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Infrastructure.Persistence.Configurations;

public sealed class RecoveryCodeConfiguration : IEntityTypeConfiguration<RecoveryCode>
{
    public void Configure(EntityTypeBuilder<RecoveryCode> builder)
    {
        builder.ToTable("recovery_codes");

        builder.HasKey(rc => rc.Id);

        builder.Property(rc => rc.CodeHash)
            .IsRequired()
            .HasMaxLength(64);

        builder.HasIndex(rc => new { rc.UserId, rc.CodeHash });

        // Two concurrent uses of the same code: the second save fails instead
        // of both succeeding.
        builder.Property(rc => rc.UsedAt).IsConcurrencyToken();

        builder.HasOne(rc => rc.User)
            .WithMany(u => u.RecoveryCodes)
            .HasForeignKey(rc => rc.UserId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
