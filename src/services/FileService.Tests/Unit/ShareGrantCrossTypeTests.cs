using FluentAssertions;
using Xunit;
using ZDrive.Shared.Auth;

namespace ZDrive.FileService.Tests.Unit;

/// <summary>
/// Domain-separation tests: ShareDownloadGrant, ShareUploadGrant and
/// ShareUploadReceipt share one HMAC key and codec, so a purpose-prefix bug
/// would let one type's token validate as another — e.g. an anonymous
/// visitor turning a download grant into a forged upload grant. Every pair,
/// both directions, must fail.
/// </summary>
[Trait("Category", "Unit")]
public sealed class ShareGrantCrossTypeTests
{
    private static readonly byte[] Key = System.Text.Encoding.UTF8.GetBytes("0123456789abcdef0123456789abcdef");

    private static string MakeDownloadGrant() => ShareDownloadGrant.Create(
        new ShareDownloadGrant.Payload(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), new string('a', 64),
            DateTimeOffset.UtcNow.AddHours(1)),
        Key);

    private static string MakeUploadGrant() => ShareUploadGrant.Create(
        new ShareUploadGrant.Payload(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), 1024,
            DateTimeOffset.UtcNow.AddHours(1)),
        Key);

    private static string MakeUploadReceipt() => ShareUploadReceipt.Create(
        new ShareUploadReceipt.Payload(Guid.NewGuid(), new string('b', 64), 1024,
            DateTimeOffset.UtcNow.AddMinutes(15)),
        Key);

    [Fact]
    public void DownloadGrant_DoesNotValidate_AsUploadGrant() =>
        ShareUploadGrant.TryValidate(MakeDownloadGrant(), Key, DateTimeOffset.UtcNow, out _).Should().BeFalse();

    [Fact]
    public void DownloadGrant_DoesNotValidate_AsUploadReceipt() =>
        ShareUploadReceipt.TryValidate(MakeDownloadGrant(), Key, DateTimeOffset.UtcNow, out _).Should().BeFalse();

    [Fact]
    public void UploadGrant_DoesNotValidate_AsDownloadGrant() =>
        ShareDownloadGrant.TryValidate(MakeUploadGrant(), Key, DateTimeOffset.UtcNow, out _).Should().BeFalse();

    [Fact]
    public void UploadGrant_DoesNotValidate_AsUploadReceipt() =>
        ShareUploadReceipt.TryValidate(MakeUploadGrant(), Key, DateTimeOffset.UtcNow, out _).Should().BeFalse();

    [Fact]
    public void UploadReceipt_DoesNotValidate_AsDownloadGrant() =>
        ShareDownloadGrant.TryValidate(MakeUploadReceipt(), Key, DateTimeOffset.UtcNow, out _).Should().BeFalse();

    [Fact]
    public void UploadReceipt_DoesNotValidate_AsUploadGrant() =>
        ShareUploadGrant.TryValidate(MakeUploadReceipt(), Key, DateTimeOffset.UtcNow, out _).Should().BeFalse();

    // Teeth check: each type still validates as ITSELF, so the cross-type
    // failures above are proof of domain separation, not of a broken codec.
    [Fact]
    public void EachType_StillValidates_AsItself()
    {
        ShareDownloadGrant.TryValidate(MakeDownloadGrant(), Key, DateTimeOffset.UtcNow, out _).Should().BeTrue();
        ShareUploadGrant.TryValidate(MakeUploadGrant(), Key, DateTimeOffset.UtcNow, out _).Should().BeTrue();
        ShareUploadReceipt.TryValidate(MakeUploadReceipt(), Key, DateTimeOffset.UtcNow, out _).Should().BeTrue();
    }
}
