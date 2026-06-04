using FluentValidation.TestHelper;
using Xunit;
using ZDrive.AuthService.Application.Commands.RefreshToken;

namespace ZDrive.AuthService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class RefreshTokenCommandValidatorTests
{
    private readonly RefreshTokenCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var result = _validator.TestValidate(new RefreshTokenCommand("some-token-value"));
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_RefreshToken_Fails()
    {
        var result = _validator.TestValidate(new RefreshTokenCommand(""));
        result.ShouldHaveValidationErrorFor(x => x.RefreshToken);
    }
}
