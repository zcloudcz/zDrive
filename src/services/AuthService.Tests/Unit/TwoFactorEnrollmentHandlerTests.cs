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

    private SetupTwoFactorCommandHandler SetupHandler() => new(_t.Db, _t.Totp, _t.Protector);
    private ConfirmTwoFactorCommandHandler ConfirmHandler() => new(_t.Db, _t.Verifier);
    private DisableTwoFactorCommandHandler DisableHandler() => new(_t.Db, _t.Hasher, _t.Verifier);

    [Fact]
    public async Task Setup_PasswordUser_StoresProtectedSecretAndReturnsUri()
    {
        var user = await _t.AddUserAsync();

        var result = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id), default);

        result.OtpAuthUri.Should().Contain($"secret={result.Secret}");
        user.TwoFactorSecretProtected.Should().NotBeNullOrEmpty().And.NotContain(result.Secret);
        _t.Protector.Unprotect(user.TwoFactorSecretProtected!).Should().Be(result.Secret);
        user.TwoFactorEnabled.Should().BeFalse("setup only starts the enrollment");
    }

    [Fact]
    public async Task Setup_EntraOnlyUser_ThrowsForbidden()
    {
        var user = await _t.AddUserAsync(password: null);

        var act = () => SetupHandler().Handle(new SetupTwoFactorCommand(user.Id), default);

        await act.Should().ThrowAsync<ForbiddenException>();
    }

    [Fact]
    public async Task Setup_AlreadyEnabled_ThrowsConflict()
    {
        var user = await _t.AddUserAsync();
        await _t.EnableTwoFactorAsync(user);

        var act = () => SetupHandler().Handle(new SetupTwoFactorCommand(user.Id), default);

        await act.Should().ThrowAsync<ConflictException>();
    }

    [Fact]
    public async Task Confirm_ValidCode_EnablesTwoFactorAndReturnsTenRecoveryCodes()
    {
        var user = await _t.AddUserAsync();
        var setup = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id), default);

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
        var setup = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id), default);
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
        var setup = await SetupHandler().Handle(new SetupTwoFactorCommand(user.Id), default);
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
}
