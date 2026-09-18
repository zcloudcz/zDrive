using FluentAssertions;
using Xunit;
using ZDrive.StorageService.Application.Services;
using ZDrive.StorageService.Domain.Entities;
using ZDrive.StorageService.Domain.Enums;

namespace ZDrive.StorageService.Tests.Unit;

/// <summary>
/// Docker-less unit test for the sweeper's selection predicate (the DB query
/// itself needs Postgres — see the Integration tier). No hand-rolled
/// IStorageDbContext fake: this pure function is the whole decision the
/// sweeper makes per session, so testing it directly is the smallest correct
/// seam, not a shortcut around one. SweepOnceAsync's candidate query now
/// filters on the same (Status == Active, ExpiresAt < now) condition in SQL
/// directly rather than pulling every Active session — ShouldSweep is still
/// the authoritative re-check taken under each session's row lock, so this
/// predicate is exactly what both the SQL filter and that re-check agree on.
/// </summary>
[Trait("Category", "Unit")]
public sealed class ExpiredUploadSessionSweeperTests
{
    private static UploadSession MakeSession(UploadSessionStatus status, DateTime expiresAt) => new()
    {
        Id = Guid.NewGuid(), UserId = Guid.NewGuid(), TenantId = Guid.NewGuid(), FileId = Guid.NewGuid(),
        FileName = "x", Status = status, TotalChunks = 1, ExpiresAt = expiresAt
    };

    [Fact]
    public void ShouldSweep_ActiveAndPastExpiry_ReturnsTrue()
    {
        var session = MakeSession(UploadSessionStatus.Active, DateTime.UtcNow.AddHours(-1));
        ExpiredUploadSessionSweeper.ShouldSweep(session, DateTime.UtcNow).Should().BeTrue();
    }

    [Fact]
    public void ShouldSweep_ActiveButNotYetExpired_ReturnsFalse()
    {
        var session = MakeSession(UploadSessionStatus.Active, DateTime.UtcNow.AddHours(1));
        ExpiredUploadSessionSweeper.ShouldSweep(session, DateTime.UtcNow).Should().BeFalse();
    }

    [Theory]
    [InlineData(UploadSessionStatus.Completed)]
    [InlineData(UploadSessionStatus.Aborted)]
    [InlineData(UploadSessionStatus.Expired)]
    public void ShouldSweep_NonActiveStatus_ReturnsFalseEvenPastExpiry(UploadSessionStatus status)
    {
        var session = MakeSession(status, DateTime.UtcNow.AddHours(-1));
        ExpiredUploadSessionSweeper.ShouldSweep(session, DateTime.UtcNow).Should().BeFalse();
    }
}
