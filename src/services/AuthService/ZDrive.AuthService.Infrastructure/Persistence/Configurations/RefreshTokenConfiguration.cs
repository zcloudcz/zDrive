using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Infrastructure.Persistence.Configurations;

public sealed class RefreshTokenConfiguration : IEntityTypeConfiguration<RefreshToken>
{
    public void Configure(EntityTypeBuilder<RefreshToken> builder)
    {
        builder.ToTable("refresh_tokens");

        builder.HasKey(rt => rt.Id);

        builder.Property(rt => rt.Token)
            .IsRequired()
            .HasMaxLength(512);

        builder.HasIndex(rt => rt.Token)
            .IsUnique();

        builder.Property(rt => rt.ExpiresAt)
            .IsRequired();

        // Null for legacy password-flow tokens; set by the Entra exchange to cap
        // a federated session's lifetime (see RefreshToken.AbsoluteExpiresAt).
        builder.Property(rt => rt.AbsoluteExpiresAt);

        builder.Property(rt => rt.CreatedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        builder.Property(rt => rt.ReplacedByToken)
            .HasMaxLength(512);

        builder.HasOne(rt => rt.User)
            .WithMany(u => u.RefreshTokens)
            .HasForeignKey(rt => rt.UserId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
