using FluentValidation.TestHelper;
using Xunit;
using ZDrive.FileService.Application.Commands.CreateShare;
using ZDrive.FileService.Domain.Enums;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class CreateShareCommandValidatorTests
{
    private readonly CreateShareCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var command = new CreateShareCommand(Guid.NewGuid(), Guid.NewGuid(), null, Permission.Read, null, null);
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_UserId_Fails()
    {
        var command = new CreateShareCommand(Guid.Empty, Guid.NewGuid(), null, Permission.Read, null, null);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.UserId);
    }

    [Fact]
    public void Empty_FileId_Fails()
    {
        var command = new CreateShareCommand(Guid.NewGuid(), Guid.Empty, null, Permission.Read, null, null);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.FileId);
    }

    [Fact]
    public void Past_ExpiresAt_Fails()
    {
        var command = new CreateShareCommand(Guid.NewGuid(), Guid.NewGuid(), null, Permission.Read, null, DateTime.UtcNow.AddDays(-1));
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.ExpiresAt);
    }

    [Fact]
    public void Invalid_Permission_Fails()
    {
        var command = new CreateShareCommand(Guid.NewGuid(), Guid.NewGuid(), null, (Permission)99, null, null);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Permission);
    }
}
