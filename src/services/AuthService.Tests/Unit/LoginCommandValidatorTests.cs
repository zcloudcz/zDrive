using FluentValidation.TestHelper;
using Xunit;
using ZDrive.AuthService.Application.Commands.Login;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class LoginCommandValidatorTests
{
    private readonly LoginCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var result = _validator.TestValidate(new LoginCommand("user@example.com", "password"));
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_Email_Fails()
    {
        var result = _validator.TestValidate(new LoginCommand("", "password"));
        result.ShouldHaveValidationErrorFor(x => x.Email);
    }

    [Fact]
    public void Empty_Password_Fails()
    {
        var result = _validator.TestValidate(new LoginCommand("user@example.com", ""));
        result.ShouldHaveValidationErrorFor(x => x.Password);
    }

    [Fact]
    public void Invalid_Email_Fails()
    {
        var result = _validator.TestValidate(new LoginCommand("not-an-email", "password"));
        result.ShouldHaveValidationErrorFor(x => x.Email);
    }
}
