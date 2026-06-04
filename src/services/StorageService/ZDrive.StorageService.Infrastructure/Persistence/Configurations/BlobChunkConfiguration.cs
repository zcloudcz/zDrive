using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.StorageService.Domain.Entities;

namespace ZDrive.StorageService.Infrastructure.Persistence.Configurations;

public sealed class BlobChunkConfiguration : IEntityTypeConfiguration<BlobChunk>
{
    public void Configure(EntityTypeBuilder<BlobChunk> builder)
    {
        builder.ToTable("blob_chunks");

        builder.HasKey(x => x.Id);

        builder.Property(x => x.FileId).IsRequired();
        builder.Property(x => x.ChunkHash).IsRequired().HasMaxLength(128);
        builder.Property(x => x.ChunkIndex).IsRequired();
        builder.Property(x => x.SizeBytes).IsRequired();
        builder.Property(x => x.BlobPath).IsRequired().HasMaxLength(1024);
        builder.Property(x => x.CreatedAt).IsRequired();

        builder.HasIndex(x => x.FileId);
        builder.HasIndex(x => new { x.FileId, x.ChunkHash }).IsUnique();
    }
}
