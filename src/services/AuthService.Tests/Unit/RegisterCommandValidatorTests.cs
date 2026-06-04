using FluentAssertions;
using FluentValidation.TestHelper;
using Xunit;
using ZDrive.AuthService.Application.Commands.Register;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class RegisterCommandValidatorTests
{
    private readonly RegisterCommandValidator _validator = new();

    [Theory]
    [InlineData("user@example.com", "Password1", "John Doe")]
    [InlineData("a@b.co", "Abcdefg1", "X")]
    public void Valid_Command_Passes(string email, string password, string displayName)
    {
        var command = new RegisterCommand(email, password, displayName);
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Theory]
    [InlineData("", "Password1", "John")]   // empty email
    [InlineData("notanemail", "Password1", "John")] // invalid email
    public void Invalid_Email_Fails(string email, string password, string displayName)
    {
        var command = new RegisterCommand(email, password, displayName);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Email);
    }

    [Theory]
    [InlineData("user@test.com", "", "John")]       // empty
    [InlineData("user@test.com", "short", "John")]  // too short
    [InlineData("user@test.com", "nouppercase1", "John")] // no uppercase
    [InlineData("user@test.com", "NOLOWERCASE1", "John")] // no lowercase
    [InlineData("user@test.com", "NoDigitsHere", "John")] // no digit
    public void Invalid_Password_Fails(string email, string password, string displayName)
    {
        var command = new RegisterCommand(email, password, displayName);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Password);
    }

    [Fact]
    public void Empty_DisplayName_Fails()
    {
        var command = new RegisterCommand("user@test.com", "Password1", "");
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.DisplayName);
    }
}
