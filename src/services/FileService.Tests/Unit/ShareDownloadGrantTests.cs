using FluentAssertions;
using Xunit;
using ZDrive.Shared.Auth;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class ShareDownloadGrantTests
{
    private static readonly byte[] Key = System.Text.Encoding.UTF8.GetBytes("0123456789abcdef0123456789abcdef");
    private static readonly byte[] OtherKey = System.Text.Encoding.UTF8.GetBytes("fedcba9876543210fedcba9876543210");

    private static ShareDownloadGrant.Payload MakePayload(DateTimeOffset? expiresAt = null) => new(
        Guid.NewGuid(),
        Guid.NewGuid(),
        Guid.NewGuid(),
        new string('a', 64),
        expiresAt ?? DateTimeOffset.UtcNow.AddHours(6));

    [Fact]
    public void Create_ThenTryValidate_RoundTripsPayload()
    {
        var payload = MakePayload();
        var grant = ShareDownloadGrant.Create(payload, Key);

        var isValid = ShareDownloadGrant.TryValidate(grant, Key, DateTimeOffset.UtcNow, out var recovered);

        isValid.Should().BeTrue();
        recovered.Should().Be(payload);
    }

    [Fact]
    public void TryValidate_TamperedPayload_ReturnsFalse()
    {
        var grant = ShareDownloadGrant.Create(MakePayload(), Key);
        var parts = grant.Split('.');
        var tampered = $"{FlipFirstByte(parts[0])}.{parts[1]}";

        var isValid = ShareDownloadGrant.TryValidate(tampered, Key, DateTimeOffset.UtcNow, out _);

        isValid.Should().BeFalse();
    }

    [Fact]
    public void TryValidate_TamperedSignature_ReturnsFalse()
    {
        var grant = ShareDownloadGrant.Create(MakePayload(), Key);
        var parts = grant.Split('.');
        var tampered = $"{parts[0]}.{FlipFirstByte(parts[1])}";

        var isValid = ShareDownloadGrant.TryValidate(tampered, Key, DateTimeOffset.UtcNow, out _);

        isValid.Should().BeFalse();
    }

    /// <summary>
    /// Decodes a base64url segment, flips a bit in its FIRST byte, and
    /// re-encodes. Deliberately not "swap the last character": for a
    /// 32-byte HMAC signature the trailing base64url character carries only
    /// 4 significant bits plus 2 always-zero padding bits, so some
    /// substitutions there decode to the exact same bytes — that made this
    /// test probabilistic (it failed roughly 1 run in a few dozen). Flipping
    /// a bit in the first byte always changes the decoded bytes.
    /// </summary>
    private static string FlipFirstByte(string base64UrlSegment)
    {
        var bytes = Base64UrlDecode(base64UrlSegment);
        bytes[0] ^= 0x01;
        return Base64UrlEncode(bytes);
    }

    private static string Base64UrlEncode(byte[] bytes) =>
        Convert.ToBase64String(bytes).Replace('+', '-').Replace('/', '_').TrimEnd('=');

    private static byte[] Base64UrlDecode(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        padded = padded.PadRight(padded.Length + ((4 - (padded.Length % 4)) % 4), '=');
        return Convert.FromBase64String(padded);
    }

    [Fact]
    public void TryValidate_WrongKey_ReturnsFalse()
    {
        var grant = ShareDownloadGrant.Create(MakePayload(), Key);

        var isValid = ShareDownloadGrant.TryValidate(grant, OtherKey, DateTimeOffset.UtcNow, out _);

        isValid.Should().BeFalse();
    }

    [Fact]
    public void TryValidate_Expired_ReturnsFalse()
    {
        var grant = ShareDownloadGrant.Create(MakePayload(DateTimeOffset.UtcNow.AddMinutes(-1)), Key);

        var isValid = ShareDownloadGrant.TryValidate(grant, Key, DateTimeOffset.UtcNow, out _);

        isValid.Should().BeFalse();
    }

    [Theory]
    [InlineData("")]
    [InlineData("a")]
    [InlineData("a.b")]
    [InlineData("not-base64!.also-not-base64!")]
    [InlineData("....")]
    public void TryValidate_GarbageInput_ReturnsFalseWithoutThrowing(string garbage)
    {
        var act = () => ShareDownloadGrant.TryValidate(garbage, Key, DateTimeOffset.UtcNow, out _);

        act.Should().NotThrow();
        act().Should().BeFalse();
    }

    [Fact]
    public void TryValidate_NullGrant_ReturnsFalse()
    {
        var isValid = ShareDownloadGrant.TryValidate(null, Key, DateTimeOffset.UtcNow, out _);

        isValid.Should().BeFalse();
    }
}
