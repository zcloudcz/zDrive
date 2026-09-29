using FluentAssertions;
using Microsoft.Extensions.Options;
using Xunit;
using ZDrive.FileService.Application.Commands.CreateFileVersion;
using ZDrive.FileService.Application.Options;
using ZDrive.FileService.Application.Services;
using ZDrive.FileService.Domain.Entities;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class VersionRetentionTests
{
    private static readonly DateTime Now = new(2026, 6, 1, 12, 0, 0, DateTimeKind.Utc);

    private sealed class FixedTime(DateTime utc) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => new(utc, TimeSpan.Zero);
    }

    // Versions 1..count; version n is (count - n + 1) * daysApart days old.
    private static List<FileVersion> Versions(int count, int daysApart = 10) =>
        Enumerable.Range(1, count).Select(n => new FileVersion
        {
            Id = Guid.NewGuid(), FileId = Guid.Empty, VersionNumber = n, BlobVersionId = $"v{n}",
            SizeBytes = 10, CreatedBy = Guid.Empty,
            CreatedAt = Now.AddDays(-(count - n + 1) * daysApart)
        }).ToList();

    [Fact]
    public void SelectPrunable_ZeroMinRetention_PrunesByCountOnly()
    {
        var options = new VersioningOptions { MaxVersionsPerFile = 3, MinRetentionDays = 0 };

        var result = VersionRetention.SelectPrunable(Versions(5), options, Now);

        // The new version takes one of the 3 slots, so 2 existing rows stay.
        result.Select(v => v.VersionNumber).Should().BeEquivalentTo([3, 2, 1]);
    }

    [Fact]
    public void SelectPrunable_YoungVersionsBeyondLimit_NotPruned()
    {
        var options = new VersioningOptions { MaxVersionsPerFile = 3, MinRetentionDays = 30 };

        // ages 5,4,3,2,1 days
        VersionRetention.SelectPrunable(Versions(5, daysApart: 1), options, Now).Should().BeEmpty();
    }

    [Fact]
    public void SelectPrunable_OldVersionsBeyondLimit_Pruned()
    {
        var options = new VersioningOptions { MaxVersionsPerFile = 3, MinRetentionDays = 35 };

        // ages 50,40,30,20,10 days; beyond the limit are v3 (30d), v2 (40d), v1 (50d).
        VersionRetention.SelectPrunable(Versions(5, daysApart: 10), options, Now)
            .Select(v => v.VersionNumber).Should().BeEquivalentTo([2, 1]);
    }

    [Fact]
    public void SelectPrunable_OldVersionInsideLimit_NotPruned()
    {
        var options = new VersioningOptions { MaxVersionsPerFile = 5, MinRetentionDays = 30 };

        VersionRetention.SelectPrunable(Versions(2, daysApart: 400), options, Now).Should().BeEmpty();
    }

    [Fact]
    public void SelectPrunable_MixedAges_OnlyOldBeyondLimitPruned()
    {
        var existing = Versions(4, daysApart: 10); // ages 40,30,20,10
        var options = new VersioningOptions { MaxVersionsPerFile = 2, MinRetentionDays = 35 };

        // Beyond the limit: v3 (20d) and v2 (30d) too young, v1 (40d) old enough.
        VersionRetention.SelectPrunable(existing, options, Now)
            .Select(v => v.VersionNumber).Should().BeEquivalentTo([1]);
    }

    [Fact]
    public void SelectPrunable_LimitDisabled_NeverPrunes()
    {
        var options = new VersioningOptions { MaxVersionsPerFile = 0, MinRetentionDays = 30 };

        VersionRetention.SelectPrunable(Versions(5), options, Now).Should().BeEmpty();
    }

    [Fact]
    public async Task Handle_YoungVersionsAboveLimit_KeptAndNewVersionAdded()
    {
        var db = InMemoryFileDbContext.Create();
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var file = new FileNode { Id = Guid.NewGuid(), TenantId = tenantId, UserId = userId, Name = "f.txt", IsFolder = false };
        db.FileNodes.Add(file);
        foreach (var v in Versions(3, daysApart: 1))
        {
            v.FileId = file.Id;
            v.CreatedBy = userId;
            db.FileVersions.Add(v);
        }
        db.SaveChanges();

        var options = Options.Create(new VersioningOptions { MaxVersionsPerFile = 2, MinRetentionDays = 30 });
        var quota = new StorageQuota(db, Options.Create(new StorageOptions { DefaultUserQuotaBytes = 1000 }));
        var handler = new CreateFileVersionCommandHandler(db, options, quota, new FixedTime(Now));

        await handler.Handle(new CreateFileVersionCommand(tenantId, userId, file.Id, "v4", SizeBytes: 10, null, null),
            CancellationToken.None);

        db.FileVersions.Count(v => v.FileId == file.Id).Should().Be(4);
    }
}
