using FluentValidation.TestHelper;
using Xunit;
using ZDrive.AuthService.Application.Commands.UpdateProfile;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class UpdateProfileCommandValidatorTests
{
    private readonly UpdateProfileCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var command = new UpdateProfileCommand(Guid.NewGuid(), "New Name", "https://example.com/avatar.png");
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Null_OptionalFields_Passes()
    {
        var command = new UpdateProfileCommand(Guid.NewGuid(), null, null);
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void TooLong_DisplayName_Fails()
    {
        var command = new UpdateProfileCommand(Guid.NewGuid(), new string('A', 201), null);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.DisplayName);
    }

    [Fact]
    public void Invalid_AvatarUrl_Fails()
    {
        var command = new UpdateProfileCommand(Guid.NewGuid(), null, "not-a-url");
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.AvatarUrl);
    }

    [Fact]
    public void Empty_UserId_Fails()
    {
        var command = new UpdateProfileCommand(Guid.Empty, "Name", null);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.UserId);
    }
}
