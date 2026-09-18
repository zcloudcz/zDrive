using FluentAssertions;
using Xunit;
using ZDrive.Shared.Auth;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class ShareDownloadGrantOptionsTests
{
    [Fact]
    public void TryGetKey_NoKeyConfigured_ReturnsFalse()
    {
        var options = new ShareDownloadGrantOptions { DownloadGrantKey = null };

        options.TryGetKey(out _).Should().BeFalse();
    }

    [Fact]
    public void TryGetKey_EmptyKey_ReturnsFalse()
    {
        var options = new ShareDownloadGrantOptions { DownloadGrantKey = "" };

        options.TryGetKey(out _).Should().BeFalse();
    }

    [Fact]
    public void TryGetKey_KeyShorterThan32Bytes_ReturnsFalse()
    {
        // 16 raw bytes, valid base64.
        var options = new ShareDownloadGrantOptions
        {
            DownloadGrantKey = Convert.ToBase64String(new byte[16])
        };

        options.TryGetKey(out _).Should().BeFalse();
    }

    [Fact]
    public void TryGetKey_NotValidBase64_ReturnsFalse()
    {
        var options = new ShareDownloadGrantOptions { DownloadGrantKey = "not-base64!!!" };

        options.TryGetKey(out _).Should().BeFalse();
    }

    [Fact]
    public void TryGetKey_ValidLongKey_ReturnsTrueWithDecodedBytes()
    {
        var raw = new byte[32];
        Random.Shared.NextBytes(raw);
        var options = new ShareDownloadGrantOptions { DownloadGrantKey = Convert.ToBase64String(raw) };

        var result = options.TryGetKey(out var key);

        result.Should().BeTrue();
        key.Should().Equal(raw);
    }
}
