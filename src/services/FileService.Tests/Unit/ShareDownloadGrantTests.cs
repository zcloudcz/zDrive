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
        // Flip one character of the payload segment — signature no longer matches.
        var tamperedPayload = parts[0][^1] == 'A' ? "B" + parts[0][1..] : "A" + parts[0][1..];
        var tampered = $"{tamperedPayload}.{parts[1]}";

        var isValid = ShareDownloadGrant.TryValidate(tampered, Key, DateTimeOffset.UtcNow, out _);

        isValid.Should().BeFalse();
    }

    [Fact]
    public void TryValidate_TamperedSignature_ReturnsFalse()
    {
        var grant = ShareDownloadGrant.Create(MakePayload(), Key);
        var parts = grant.Split('.');
        var tamperedSignature = parts[1][^1] == 'A' ? "B" + parts[1][1..] : "A" + parts[1][1..];
        var tampered = $"{parts[0]}.{tamperedSignature}";

        var isValid = ShareDownloadGrant.TryValidate(tampered, Key, DateTimeOffset.UtcNow, out _);

        isValid.Should().BeFalse();
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
