using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZDrive.FileService.Domain.Entities;

namespace ZDrive.FileService.Infrastructure.Persistence.Configurations;

public sealed class FileNodeConfiguration : IEntityTypeConfiguration<FileNode>
{
    // Shared with ExceptionHandlingMiddleware, which matches this index's
    // name in the unique-violation constraint pattern (PR #12 review round
    // 5, N2) — keeping both in sync by hand was a magic-string trap.
    public const string NameUniqueIndexName = "ix_file_nodes_tenant_id_user_id_parent_id_name_normalized";

    public void Configure(EntityTypeBuilder<FileNode> builder)
    {
        builder.ToTable("file_nodes");

        builder.HasKey(f => f.Id);

        builder.Property(f => f.Name)
            .IsRequired()
            .HasMaxLength(512);

        builder.Property(f => f.MimeType)
            .HasMaxLength(256);

        builder.Property(f => f.BlobPath)
            .HasMaxLength(2048);

        builder.Property(f => f.ManifestHash)
            .HasMaxLength(128);

        builder.Property(f => f.CreatedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        builder.Property(f => f.UpdatedAt)
            .HasDefaultValueSql("now() at time zone 'utc'");

        // Indexes
        builder.HasIndex(f => f.ParentId);

        builder.HasIndex(f => new { f.TenantId, f.UserId });

        builder.HasIndex(f => f.IsDeleted);

        // Case-insensitive sibling-name uniqueness: on NTFS and default APFS
        // "Photos" and "photos" are the same directory, so two file_nodes
        // rows that differ only by case are not a cosmetic duplicate, they
        // are a name collision the client cannot represent on disk (see PR
        // #12 review round 3, B1). A generated lower(name) column plus a
        // unique index on it (instead of an expression index) keeps this
        // queryable/indexable the same way name_tsv already is below, and
        // supersedes the old case-sensitive unique index — two rows with
        // identical case now collide here too, so that index is dropped.
        builder.Property<string>("name_normalized")
            .HasColumnName("name_normalized")
            .HasMaxLength(512)
            .HasComputedColumnSql("lower(name)", stored: true);

        // ParentId is NULL for root-level items — the most important place
        // for this uniqueness rule, since the root is the synced folder
        // itself. Postgres treats NULLs as distinct in a unique index by
        // default, so without AreNullsDistinct(false) the index would not
        // stop "Photos" and "photos" from coexisting at the root; only the
        // handlers' pre-check would, and two concurrent creates can race
        // past that (PR #12 review round 4). Requires Postgres 15+ (the
        // stack runs 16).
        builder.HasIndex(new[] { nameof(FileNode.TenantId), nameof(FileNode.UserId), nameof(FileNode.ParentId), "name_normalized" })
            .IsUnique()
            .HasFilter("is_deleted = false")
            .AreNullsDistinct(false)
            .HasDatabaseName(NameUniqueIndexName);

        // Self-referencing relationship
        builder.HasOne(f => f.Parent)
            .WithMany(f => f.Children)
            .HasForeignKey(f => f.ParentId)
            .OnDelete(DeleteBehavior.Restrict);

        // PostgreSQL full-text search: generated tsvector column on Name.
        // The column is created via raw SQL in the migration, but we configure
        // it as a shadow property so EF Core knows about it for queries.
        builder.Property<NpgsqlTypes.NpgsqlTsVector>("name_tsv")
            .HasColumnName("name_tsv")
            .IsRequired(false)
            .HasComputedColumnSql("to_tsvector('simple', name)", stored: true);

        builder.HasIndex("name_tsv")
            .HasMethod("GIN");
    }
}
