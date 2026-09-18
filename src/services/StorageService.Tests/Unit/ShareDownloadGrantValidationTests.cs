using FluentAssertions;
using Xunit;
using ZDrive.Shared.Auth;

namespace ZDrive.StorageService.Tests.Unit;

/// <summary>
/// StorageService's own exercise of ShareDownloadGrant/ShareDownloadGrantOptions
/// (SharedStorageController.ValidateGrantOrThrow) — the fail-closed "no key
/// configured" behavior in particular, since that's the difference between
/// this feature being off and it being live.
/// </summary>
[Trait("Category", "Unit")]
public sealed class ShareDownloadGrantValidationTests
{
    [Fact]
    public void ValidateGrant_KeyNotConfigured_NeverValidates()
    {
        var options = new ShareDownloadGrantOptions { DownloadGrantKey = null };

        options.TryGetKey(out _).Should().BeFalse("a missing key must fail closed, not fall back to some default");
    }

    [Fact]
    public void ValidateGrant_ValidGrantWithConfiguredKey_Validates()
    {
        var options = new ShareDownloadGrantOptions
        {
            DownloadGrantKey = Convert.ToBase64String(new byte[32])
        };
        options.TryGetKey(out var key).Should().BeTrue();

        var payload = new ShareDownloadGrant.Payload(
            Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), new string('a', 64), DateTimeOffset.UtcNow.AddHours(1));
        var grant = ShareDownloadGrant.Create(payload, key);

        ShareDownloadGrant.TryValidate(grant, key, DateTimeOffset.UtcNow, out var recovered).Should().BeTrue();
        recovered.Should().Be(payload);
    }
}
