using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.AuthService.Domain.Entities;

namespace ZDrive.AuthService.Infrastructure.Persistence.Configurations;

public sealed class ExternalIdentityConfiguration : IEntityTypeConfiguration<ExternalIdentity>
{
    public void Configure(EntityTypeBuilder<ExternalIdentity> builder)
    {
        builder.ToTable("external_identities");

        builder.HasKey(ei => ei.Id);

        builder.Property(ei => ei.ProviderTenantId)
            .IsRequired()
            .HasMaxLength(64);

        builder.Property(ei => ei.ObjectId)
            .IsRequired()
            .HasMaxLength(64);

        builder.HasIndex(ei => new { ei.ProviderTenantId, ei.ObjectId })
            .IsUnique();

        builder.Property(ei => ei.CreatedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        builder.HasOne(ei => ei.User)
            .WithMany()
            .HasForeignKey(ei => ei.UserId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
