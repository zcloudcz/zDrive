using FluentAssertions;
using FluentValidation;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZDrive.AuthService.Application.Commands.ConfirmTwoFactor;
using ZDrive.AuthService.Application.Commands.DisableTwoFactor;
using ZDrive.AuthService.Application.Commands.SetupTwoFactor;
using ZDrive.AuthService.Tests.Fakes;
using ZDrive.Shared.Exceptions;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class TwoFactorEnrollmentHandlerTests
{
    private readonly TwoFactorTestSupport _t = new();

    private SetupTwoFactorCommandHandler SetupHandler() => new(_t.Db, _t.Hasher, _t.Totp, _t.Protector, _t.Verifier);
    private ConfirmTwoFactorCommandHandler ConfirmHandler() => new(_t.Db, _t.Verifier);
    private DisableTwoFactorCommandHandler DisableHandler() => new(_t.Db, _t.Hasher, _t.Verifier);

    [Fact]
    public async Task Setup_PasswordUser_StoresProtectedSecretAndReturnsUri()
    {
        var user = await _t.AddUserAsync();

        var result = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id, "Password1"), default);

        result.OtpAuthUri.Should().Contain($"secret={result.Secret}");
        user.TwoFactorSecretProtected.Should().NotBeNullOrEmpty().And.NotContain(result.Secret);
        _t.Protector.Unprotect(user.TwoFactorSecretProtected!).Should().Be(result.Secret);
        user.TwoFactorEnabled.Should().BeFalse("setup only starts the enrollment");
    }

    [Fact]
    public async Task Setup_EntraOnlyUser_ThrowsForbidden()
    {
        var user = await _t.AddUserAsync(password: null);

        var act = () => SetupHandler().Handle(new SetupTwoFactorCommand(user.Id, "Password1"), default);

        await act.Should().ThrowAsync<ForbiddenException>();
    }

    [Fact]
    public async Task Setup_AlreadyEnabled_ThrowsConflict()
    {
        var user = await _t.AddUserAsync();
        await _t.EnableTwoFactorAsync(user);

        var act = () => SetupHandler().Handle(new SetupTwoFactorCommand(user.Id, "Password1"), default);

        await act.Should().ThrowAsync<ConflictException>();
    }

    [Fact]
    public async Task Confirm_ValidCode_EnablesTwoFactorAndReturnsTenRecoveryCodes()
    {
        var user = await _t.AddUserAsync();
        var setup = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id, "Password1"), default);

        var result = await ConfirmHandler().Handle(
            new ConfirmTwoFactorCommand(user.Id, TwoFactorTestSupport.CodeFor(setup.Secret)), default);

        user.TwoFactorEnabled.Should().BeTrue();
        result.RecoveryCodes.Should().HaveCount(10).And.OnlyHaveUniqueItems();
        (await _t.Db.RecoveryCodes.CountAsync(c => c.UserId == user.Id)).Should().Be(10);
        _t.Db.RecoveryCodes.Select(c => c.CodeHash).ToList()
            .Should().NotContain(result.RecoveryCodes, "recovery codes are stored hashed");
    }

    [Fact]
    public async Task Confirm_WrongCode_ThrowsAndStaysDisabled()
    {
        var user = await _t.AddUserAsync();
        var setup = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id, "Password1"), default);
        var valid = TwoFactorTestSupport.CodeFor(setup.Secret);
        var wrong = valid == "000000" ? "000001" : "000000";

        var act = () => ConfirmHandler().Handle(new ConfirmTwoFactorCommand(user.Id, wrong), default);

        await act.Should().ThrowAsync<ValidationException>();
        user.TwoFactorEnabled.Should().BeFalse();
    }

    [Fact]
    public async Task Confirm_WithoutSetup_Throws()
    {
        var user = await _t.AddUserAsync();

        var act = () => ConfirmHandler().Handle(new ConfirmTwoFactorCommand(user.Id, "123456"), default);

        await act.Should().ThrowAsync<ValidationException>();
    }

    [Fact]
    public async Task Disable_ValidPasswordAndCode_ClearsEverything()
    {
        var user = await _t.AddUserAsync("Password1");
        var setup = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id, "Password1"), default);
        await ConfirmHandler().Handle(new ConfirmTwoFactorCommand(user.Id, TwoFactorTestSupport.CodeFor(setup.Secret)), default);
        // The confirm code used the current step; disable needs a later one.
        var nextCode = TwoFactorTestSupport.CodeFor(setup.Secret, DateTime.UtcNow.AddSeconds(30));

        await DisableHandler().Handle(new DisableTwoFactorCommand(user.Id, "Password1", nextCode), default);

        user.TwoFactorEnabled.Should().BeFalse();
        user.TwoFactorSecretProtected.Should().BeNull();
        (await _t.Db.RecoveryCodes.AnyAsync(c => c.UserId == user.Id)).Should().BeFalse();
    }

    [Fact]
    public async Task Disable_WrongPassword_Throws()
    {
        var user = await _t.AddUserAsync("Password1");
        var secret = await _t.EnableTwoFactorAsync(user);

        var act = () => DisableHandler().Handle(
            new DisableTwoFactorCommand(user.Id, "WrongPassword1", TwoFactorTestSupport.CodeFor(secret)), default);

        await act.Should().ThrowAsync<ValidationException>();
        user.TwoFactorEnabled.Should().BeTrue();
    }

    [Fact]
    public async Task Disable_NotEnabled_ThrowsConflict()
    {
        var user = await _t.AddUserAsync("Password1");

        var act = () => DisableHandler().Handle(new DisableTwoFactorCommand(user.Id, "Password1", "123456"), default);

        await act.Should().ThrowAsync<ConflictException>();
    }

    [Fact]
    public async Task Setup_WrongPassword_ThrowsAndStoresNothing()
    {
        var user = await _t.AddUserAsync("Password1");

        var act = () => SetupHandler().Handle(new SetupTwoFactorCommand(user.Id, "WrongPassword1"), default);

        await act.Should().ThrowAsync<ValidationException>();
        user.TwoFactorSecretProtected.Should().BeNull();
    }

    [Fact]
    public async Task Setup_PendingSecretYoungerThanTenMinutes_ReturnsTheSameSecret()
    {
        var user = await _t.AddUserAsync();
        var first = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id, "Password1"), default);

        var second = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id, "Password1"), default);

        second.Secret.Should().Be(first.Secret);
    }

    [Fact]
    public async Task Setup_PendingSecretOlderThanTenMinutes_IssuesNewSecretAndResetsReplayStep()
    {
        var user = await _t.AddUserAsync();
        var first = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id, "Password1"), default);
        user.TwoFactorSecretCreatedAt = DateTime.UtcNow.AddMinutes(-11);
        var guard = await _t.Db.TwoFactorGuards.SingleAsync(g => g.UserId == user.Id);
        guard.LastUsedStep = 999_999_999;
        await _t.Db.SaveChangesAsync();

        var second = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id, "Password1"), default);

        second.Secret.Should().NotBe(first.Secret);
        (await _t.Db.TwoFactorGuards.SingleAsync(g => g.UserId == user.Id)).LastUsedStep.Should().BeNull();
    }

    [Fact]
    public async Task Confirm_ExistingRefreshTokens_AreRevokedAndAFreshPairIsReturned()
    {
        var user = await _t.AddUserAsync();
        var old = new ZDrive.AuthService.Domain.Entities.RefreshToken
        {
            Id = Guid.NewGuid(), Token = "old-session", UserId = user.Id, ExpiresAt = DateTime.UtcNow.AddDays(1)
        };
        _t.Db.RefreshTokens.Add(old);
        await _t.Db.SaveChangesAsync();
        var setup = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id, "Password1"), default);

        var result = await ConfirmHandler().Handle(
            new ConfirmTwoFactorCommand(user.Id, TwoFactorTestSupport.CodeFor(setup.Secret)), default);

        old.RevokedAt.Should().NotBeNull();
        result.RefreshToken.Should().NotBe("old-session");
        (await _t.Db.RefreshTokens.SingleAsync(t => t.Token == result.RefreshToken)).IsActive.Should().BeTrue();
    }

    [Fact]
    public async Task Disable_ExistingRefreshTokens_AreRevokedAndAFreshPairIsReturned()
    {
        var user = await _t.AddUserAsync("Password1");
        var secret = await _t.EnableTwoFactorAsync(user);
        var old = new ZDrive.AuthService.Domain.Entities.RefreshToken
        {
            Id = Guid.NewGuid(), Token = "old-session", UserId = user.Id, ExpiresAt = DateTime.UtcNow.AddDays(1)
        };
        _t.Db.RefreshTokens.Add(old);
        await _t.Db.SaveChangesAsync();

        var tokens = await DisableHandler().Handle(
            new DisableTwoFactorCommand(user.Id, "Password1", TwoFactorTestSupport.CodeFor(secret)), default);

        old.RevokedAt.Should().NotBeNull();
        tokens.RefreshToken.Should().NotBe("old-session");
    }

    [Fact]
    public async Task Disable_WrongPasswordAndWrongCode_GiveTheIdenticalError()
    {
        var user = await _t.AddUserAsync("Password1");
        var secret = await _t.EnableTwoFactorAsync(user);
        var valid = TwoFactorTestSupport.CodeFor(secret);
        var wrong = valid == "000000" ? "000001" : "000000";

        var badPassword = await FluentActions
            .Awaiting(() => DisableHandler().Handle(new DisableTwoFactorCommand(user.Id, "WrongPassword1", valid), default))
            .Should().ThrowAsync<ValidationException>();
        var badCode = await FluentActions
            .Awaiting(() => DisableHandler().Handle(new DisableTwoFactorCommand(user.Id, "Password1", wrong), default))
            .Should().ThrowAsync<ValidationException>();

        badPassword.Which.Errors.Select(e => (e.PropertyName, e.ErrorMessage))
            .Should().Equal(badCode.Which.Errors.Select(e => (e.PropertyName, e.ErrorMessage)));
    }

    [Fact]
    public async Task Disable_FailuresCountTowardThePerUserCap_EvenForTheCorrectCodeAfterwards()
    {
        var t = new TwoFactorTestSupport(maxFailedAttempts: 3);
        var user = await t.AddUserAsync("Password1");
        var secret = await t.EnableTwoFactorAsync(user);
        var handler = new DisableTwoFactorCommandHandler(t.Db, t.Hasher, t.Verifier);
        for (var i = 0; i < 3; i++)
        {
            await FluentActions
                .Awaiting(() => handler.Handle(new DisableTwoFactorCommand(user.Id, "WrongPassword1", "123456"), default))
                .Should().ThrowAsync<ValidationException>();
        }

        var act = () => handler.Handle(
            new DisableTwoFactorCommand(user.Id, "Password1", TwoFactorTestSupport.CodeFor(secret)), default);

        await act.Should().ThrowAsync<ValidationException>();
        user.TwoFactorEnabled.Should().BeTrue();
    }
}
