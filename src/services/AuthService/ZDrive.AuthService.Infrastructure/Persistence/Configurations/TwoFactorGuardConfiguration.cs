using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Infrastructure.Persistence.Configurations;

public sealed class TwoFactorGuardConfiguration : IEntityTypeConfiguration<TwoFactorGuard>
{
    public void Configure(EntityTypeBuilder<TwoFactorGuard> builder)
    {
        builder.ToTable("two_factor_guards");

        builder.HasKey(g => g.UserId);

        // Concurrent updates (replayed TOTP code, parallel attempts): the
        // second save fails instead of silently overwriting the first.
        builder.Property(g => g.Version).IsConcurrencyToken();

        builder.HasOne(g => g.User)
            .WithOne()
            .HasForeignKey<TwoFactorGuard>(g => g.UserId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
