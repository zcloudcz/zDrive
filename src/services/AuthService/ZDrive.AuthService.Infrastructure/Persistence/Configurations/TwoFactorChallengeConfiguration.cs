using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Infrastructure.Persistence.Configurations;

public sealed class TwoFactorChallengeConfiguration : IEntityTypeConfiguration<TwoFactorChallenge>
{
    public void Configure(EntityTypeBuilder<TwoFactorChallenge> builder)
    {
        builder.ToTable("two_factor_challenges");

        builder.HasKey(c => c.Id);

        builder.Property(c => c.TokenHash)
            .IsRequired()
            .HasMaxLength(64);

        builder.HasIndex(c => c.TokenHash)
            .IsUnique();

        // Two concurrent completions of one challenge: the second save fails.
        builder.Property(c => c.UsedAt).IsConcurrencyToken();

        builder.HasOne(c => c.User)
            .WithMany()
            .HasForeignKey(c => c.UserId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
