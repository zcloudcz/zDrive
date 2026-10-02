using FluentAssertions;
using Xunit;
using ZDrive.AuthService.Infrastructure.Auth;
using ZDrive.AuthService.Tests.Fakes;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class TotpServiceTests
{
    private readonly TotpService _totp = new();

    [Fact]
    public void TryVerify_CurrentCode_Succeeds()
    {
        var secret = _totp.GenerateSecret();

        var ok = _totp.TryVerify(secret, TwoFactorTestSupport.CodeFor(secret), null, out var step);

        ok.Should().BeTrue();
        step.Should().BeGreaterThan(0);
    }

    [Theory]
    [InlineData(-30)]
    [InlineData(30)]
    public void TryVerify_AdjacentStep_Succeeds(int offsetSeconds)
    {
        var secret = _totp.GenerateSecret();
        var code = TwoFactorTestSupport.CodeFor(secret, DateTime.UtcNow.AddSeconds(offsetSeconds));

        _totp.TryVerify(secret, code, null, out _).Should().BeTrue();
    }

    [Fact]
    public void TryVerify_TwoStepsAway_Fails()
    {
        var secret = _totp.GenerateSecret();
        var code = TwoFactorTestSupport.CodeFor(secret, DateTime.UtcNow.AddSeconds(-90));

        _totp.TryVerify(secret, code, null, out _).Should().BeFalse();
    }

    [Fact]
    public void TryVerify_SameStepAgain_Fails()
    {
        var secret = _totp.GenerateSecret();
        var code = TwoFactorTestSupport.CodeFor(secret);
        _totp.TryVerify(secret, code, null, out var step).Should().BeTrue();

        _totp.TryVerify(secret, code, step, out _).Should().BeFalse();
    }

    [Fact]
    public void TryVerify_WrongCode_Fails()
    {
        var secret = _totp.GenerateSecret();
        var wrong = TwoFactorTestSupport.CodeFor(secret) == "000000" ? "000001" : "000000";

        _totp.TryVerify(secret, wrong, null, out _).Should().BeFalse();
    }

    [Fact]
    public void BuildOtpAuthUri_ContainsSecretIssuerAndEscapedAccount()
    {
        var uri = _totp.BuildOtpAuthUri("SECRET", "a+b@example.com");

        uri.Should().Be("otpauth://totp/zDrive:a%2Bb%40example.com?secret=SECRET&issuer=zDrive&algorithm=SHA1&digits=6&period=30");
    }
}
