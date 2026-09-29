using FluentAssertions;
using FluentValidation;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZDrive.AuthService.Application.Auth;
using ZDrive.AuthService.Application.Commands.Login;
using ZDrive.AuthService.Application.Commands.LoginTwoFactor;
using ZDrive.AuthService.Domain.Entities;
using ZDrive.AuthService.Tests.Fakes;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class LoginTwoFactorCommandHandlerTests
{
    private readonly TwoFactorTestSupport _t = new();

    private LoginCommandHandler LoginHandler() => new(_t.Db, _t.Hasher, new FakeJwtTokenGenerator());
    private LoginTwoFactorCommandHandler TwoFactorHandler() => new(_t.Db, new FakeJwtTokenGenerator(), _t.Verifier);

    private async Task<(User user, string secret, string challenge)> LoginToChallengeAsync()
    {
        var user = await _t.AddUserAsync("Password1");
        var secret = await _t.EnableTwoFactorAsync(user);
        var login = await LoginHandler().Handle(new LoginCommand(user.Email, "Password1"), default);
        return (user, secret, login.ChallengeToken!);
    }

    [Fact]
    public async Task Login_UserWithoutTwoFactor_ReturnsTokensAndNoChallenge()
    {
        var user = await _t.AddUserAsync("Password1");

        var result = await LoginHandler().Handle(new LoginCommand(user.Email, "Password1"), default);

        result.TwoFactorRequired.Should().BeFalse();
        result.AccessToken.Should().NotBeNullOrEmpty();
        result.RefreshToken.Should().NotBeNullOrEmpty();
        result.ChallengeToken.Should().BeNull();
    }

    [Fact]
    public async Task Login_UserWithTwoFactor_ReturnsChallengeAndNoTokens()
    {
        var user = await _t.AddUserAsync("Password1");
        await _t.EnableTwoFactorAsync(user);

        var result = await LoginHandler().Handle(new LoginCommand(user.Email, "Password1"), default);

        result.TwoFactorRequired.Should().BeTrue();
        result.ChallengeToken.Should().NotBeNullOrEmpty();
        result.AccessToken.Should().BeNull();
        result.RefreshToken.Should().BeNull();
        (await _t.Db.RefreshTokens.AnyAsync()).Should().BeFalse();
        _t.Db.TwoFactorChallenges.Single().TokenHash.Should().NotBe(result.ChallengeToken, "only a hash is stored");
    }

    [Fact]
    public async Task Login_TwoFactorUserWrongPassword_ThrowsWithoutChallenge()
    {
        var user = await _t.AddUserAsync("Password1");
        await _t.EnableTwoFactorAsync(user);

        var act = () => LoginHandler().Handle(new LoginCommand(user.Email, "WrongPassword1"), default);

        await act.Should().ThrowAsync<ZDrive.Shared.Exceptions.NotFoundException>();
        (await _t.Db.TwoFactorChallenges.AnyAsync()).Should().BeFalse();
    }

    [Fact]
    public async Task LoginTwoFactor_ValidCode_IssuesTokensAndConsumesChallenge()
    {
        var (user, secret, challenge) = await LoginToChallengeAsync();

        var tokens = await TwoFactorHandler().Handle(
            new LoginTwoFactorCommand(challenge, TwoFactorTestSupport.CodeFor(secret), null), default);

        tokens.AccessToken.Should().NotBeNullOrEmpty();
        tokens.RefreshToken.Should().NotBeNullOrEmpty();
        _t.Db.TwoFactorChallenges.Single().UsedAt.Should().NotBeNull();
        user.LastLoginAt.Should().NotBeNull();
    }

    [Fact]
    public async Task LoginTwoFactor_WrongCode_ThrowsAndIssuesNoTokens()
    {
        var (_, secret, challenge) = await LoginToChallengeAsync();
        var valid = TwoFactorTestSupport.CodeFor(secret);
        var wrong = valid == "000000" ? "000001" : "000000";

        var act = () => TwoFactorHandler().Handle(new LoginTwoFactorCommand(challenge, wrong, null), default);

        await act.Should().ThrowAsync<ValidationException>();
        (await _t.Db.RefreshTokens.AnyAsync()).Should().BeFalse();
        _t.Db.TwoFactorChallenges.Single().FailedAttempts.Should().Be(1);
    }

    [Fact]
    public async Task LoginTwoFactor_TooManyWrongCodes_BurnsChallengeEvenForCorrectCode()
    {
        var (_, secret, challenge) = await LoginToChallengeAsync();
        var valid = TwoFactorTestSupport.CodeFor(secret);
        var wrong = valid == "000000" ? "000001" : "000000";

        for (var i = 0; i < TwoFactorChallenge.MaxFailedAttempts; i++)
        {
            var attempt = () => TwoFactorHandler().Handle(new LoginTwoFactorCommand(challenge, wrong, null), default);
            await attempt.Should().ThrowAsync<ValidationException>();
        }

        var act = () => TwoFactorHandler().Handle(new LoginTwoFactorCommand(challenge, valid, null), default);

        await act.Should().ThrowAsync<ValidationException>();
    }

    [Fact]
    public async Task LoginTwoFactor_ChallengeReused_Throws()
    {
        var (_, secret, challenge) = await LoginToChallengeAsync();
        await TwoFactorHandler().Handle(
            new LoginTwoFactorCommand(challenge, TwoFactorTestSupport.CodeFor(secret), null), default);

        // A fresh, valid code for the next step — only the challenge is spent.
        var nextCode = TwoFactorTestSupport.CodeFor(secret, DateTime.UtcNow.AddSeconds(30));
        var act = () => TwoFactorHandler().Handle(new LoginTwoFactorCommand(challenge, nextCode, null), default);

        await act.Should().ThrowAsync<ValidationException>();
    }

    [Fact]
    public async Task LoginTwoFactor_ExpiredChallenge_Throws()
    {
        var (_, secret, challenge) = await LoginToChallengeAsync();
        _t.Db.TwoFactorChallenges.Single().ExpiresAt = DateTime.UtcNow.AddSeconds(-1);
        await _t.Db.SaveChangesAsync();

        var act = () => TwoFactorHandler().Handle(
            new LoginTwoFactorCommand(challenge, TwoFactorTestSupport.CodeFor(secret), null), default);

        await act.Should().ThrowAsync<ValidationException>();
    }

    [Fact]
    public async Task LoginTwoFactor_UnknownChallenge_Throws()
    {
        var act = () => TwoFactorHandler().Handle(new LoginTwoFactorCommand("nope", "123456", null), default);

        await act.Should().ThrowAsync<ValidationException>();
    }

    [Fact]
    public async Task LoginTwoFactor_SameTotpCodeTwice_SecondLoginRejected()
    {
        var (user, secret, challenge) = await LoginToChallengeAsync();
        var code = TwoFactorTestSupport.CodeFor(secret);
        await TwoFactorHandler().Handle(new LoginTwoFactorCommand(challenge, code, null), default);

        var second = (await LoginHandler().Handle(new LoginCommand(user.Email, "Password1"), default)).ChallengeToken!;
        var act = () => TwoFactorHandler().Handle(new LoginTwoFactorCommand(second, code, null), default);

        await act.Should().ThrowAsync<ValidationException>();
    }

    [Fact]
    public async Task LoginTwoFactor_RecoveryCode_WorksOnce()
    {
        var (user, _, challenge) = await LoginToChallengeAsync();
        var codes = await _t.Verifier.ReplaceRecoveryCodesAsync(user, default);
        await _t.Db.SaveChangesAsync();

        var tokens = await TwoFactorHandler().Handle(new LoginTwoFactorCommand(challenge, null, codes[0]), default);
        tokens.AccessToken.Should().NotBeNullOrEmpty();

        var second = (await LoginHandler().Handle(new LoginCommand(user.Email, "Password1"), default)).ChallengeToken!;
        var act = () => TwoFactorHandler().Handle(new LoginTwoFactorCommand(second, null, codes[0]), default);
        await act.Should().ThrowAsync<ValidationException>();
    }

    [Fact]
    public async Task LoginTwoFactor_RecoveryCodeLowercaseWithoutDash_Accepted()
    {
        var (user, _, challenge) = await LoginToChallengeAsync();
        var codes = await _t.Verifier.ReplaceRecoveryCodesAsync(user, default);
        await _t.Db.SaveChangesAsync();

        var typed = codes[0].Replace("-", "").ToLowerInvariant();
        var tokens = await TwoFactorHandler().Handle(new LoginTwoFactorCommand(challenge, null, typed), default);

        tokens.AccessToken.Should().NotBeNullOrEmpty();
    }

    [Fact]
    public void Validator_BothOrNeitherCode_Fails()
    {
        var validator = new LoginTwoFactorCommandValidator();

        validator.Validate(new LoginTwoFactorCommand("c", "123456", "ABCDE-ABCDE")).IsValid.Should().BeFalse();
        validator.Validate(new LoginTwoFactorCommand("c", null, null)).IsValid.Should().BeFalse();
        validator.Validate(new LoginTwoFactorCommand("c", "123456", null)).IsValid.Should().BeTrue();
    }
}
