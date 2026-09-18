using FluentAssertions;
using Microsoft.Extensions.Options;
using Xunit;
using ZDrive.FileService.Application.Options;
using ZDrive.FileService.Application.Services;
using ZDrive.FileService.Domain.Entities;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// Handler-level tests for the quota aggregate (Package B), run against EF
/// Core InMemory — no Docker needed.
/// </summary>
[Trait("Category", "Unit")]
public sealed class StorageQuotaTests
{
    private const long DefaultLimit = 1000;

    private static StorageQuota CreateSut(InMemoryFileDbContext db, long defaultLimit = DefaultLimit) =>
        new(db, Options.Create(new StorageOptions { DefaultUserQuotaBytes = defaultLimit }));

    private static (InMemoryFileDbContext Db, Guid TenantId, Guid UserId) SeedFileWithVersion(
        long sizeBytes, bool isDeleted = false)
    {
        var db = InMemoryFileDbContext.Create();
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();

        var file = new FileNode
        {
            Id = Guid.NewGuid(), TenantId = tenantId, UserId = userId,
            Name = "f.txt", IsFolder = false, IsDeleted = isDeleted
        };
        db.FileNodes.Add(file);
        db.FileVersions.Add(new FileVersion
        {
            Id = Guid.NewGuid(), FileId = file.Id, VersionNumber = 1,
            BlobVersionId = "v1", SizeBytes = sizeBytes, CreatedBy = userId
        });
        db.SaveChanges();

        return (db, tenantId, userId);
    }

    [Fact]
    public async Task GetUsageAsync_NoClaim_FallsBackToConfigDefault()
    {
        var db = InMemoryFileDbContext.Create();
        var sut = CreateSut(db);

        var usage = await sut.GetUsageAsync(Guid.NewGuid(), Guid.NewGuid(), claimLimit: null, CancellationToken.None);

        usage.LimitBytes.Should().Be(DefaultLimit);
    }

    [Fact]
    public async Task GetUsageAsync_WithClaim_OverridesConfigDefault()
    {
        var db = InMemoryFileDbContext.Create();
        var sut = CreateSut(db);

        var usage = await sut.GetUsageAsync(Guid.NewGuid(), Guid.NewGuid(), claimLimit: 42, CancellationToken.None);

        usage.LimitBytes.Should().Be(42);
    }

    [Fact]
    public async Task GetUsageAsync_TrashedNodeVersion_StillCounted()
    {
        var (db, tenantId, userId) = SeedFileWithVersion(sizeBytes: 300, isDeleted: true);
        var sut = CreateSut(db);

        var usage = await sut.GetUsageAsync(tenantId, userId, null, CancellationToken.None);

        usage.UsedBytes.Should().Be(300);
    }

    [Fact]
    public async Task GetUsageAsync_OldSupersededVersion_StillCounted()
    {
        var (db, tenantId, userId) = SeedFileWithVersion(sizeBytes: 100);
        var fileId = db.FileNodes.Single().Id;
        // A second version on the same file — the first one is "old" but is
        // not deleted from file_versions, so it must still count.
        db.FileVersions.Add(new FileVersion
        {
            Id = Guid.NewGuid(), FileId = fileId, VersionNumber = 2,
            BlobVersionId = "v2", SizeBytes = 200, CreatedBy = userId
        });
        await db.SaveChangesAsync();
        var sut = CreateSut(db);

        var usage = await sut.GetUsageAsync(tenantId, userId, null, CancellationToken.None);

        usage.UsedBytes.Should().Be(300);
    }

    [Fact]
    public async Task GetUsageAsync_PermanentlyDeletedNode_FreesSpace()
    {
        var (db, tenantId, userId) = SeedFileWithVersion(sizeBytes: 300, isDeleted: true);
        // EmptyTrash removes the FileNode; file_versions cascades with it
        // (FileVersionConfiguration.OnDelete(Cascade)) — InMemory honors the
        // configured delete behavior via SaveChanges fixup.
        db.FileNodes.RemoveRange(db.FileNodes);
        db.FileVersions.RemoveRange(db.FileVersions);
        await db.SaveChangesAsync();
        var sut = CreateSut(db);

        var usage = await sut.GetUsageAsync(tenantId, userId, null, CancellationToken.None);

        usage.UsedBytes.Should().Be(0);
    }

    [Fact]
    public async Task EnsureCanStoreAsync_AlreadyAtLimit_OneMoreByteRefused()
    {
        var (db, tenantId, userId) = SeedFileWithVersion(sizeBytes: 100);
        var sut = CreateSut(db, defaultLimit: 100);

        var act = () => sut.EnsureCanStoreAsync(tenantId, userId, null, 1, CancellationToken.None);

        var ex = await act.Should().ThrowAsync<QuotaExceededException>();
        ex.Which.LimitBytes.Should().Be(100);
        ex.Which.UsedBytes.Should().Be(100);
    }

    [Fact]
    public async Task EnsureCanStoreAsync_OneByteUnderLimit_Accepted()
    {
        var (db, tenantId, userId) = SeedFileWithVersion(sizeBytes: 99);
        var sut = CreateSut(db, defaultLimit: 100);

        var act = () => sut.EnsureCanStoreAsync(tenantId, userId, null, 1, CancellationToken.None);

        await act.Should().NotThrowAsync();
    }
}
