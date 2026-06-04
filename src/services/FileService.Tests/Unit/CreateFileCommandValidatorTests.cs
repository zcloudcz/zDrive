using FluentAssertions;
using FluentValidation.TestHelper;
using Xunit;
using ZDrive.FileService.Application.Commands.CreateFile;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class CreateFileCommandValidatorTests
{
    private readonly CreateFileCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var command = new CreateFileCommand(Guid.NewGuid(), Guid.NewGuid(), null, "Documents", true, null, null, null, null);
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_Name_Fails()
    {
        var command = new CreateFileCommand(Guid.NewGuid(), Guid.NewGuid(), null, "", true, null, null, null, null);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Name);
    }

    [Fact]
    public void Name_Too_Long_Fails()
    {
        var command = new CreateFileCommand(Guid.NewGuid(), Guid.NewGuid(), null, new string('a', 513), true, null, null, null, null);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Name);
    }

    [Fact]
    public void Empty_UserId_Fails()
    {
        var command = new CreateFileCommand(Guid.Empty, Guid.NewGuid(), null, "test", true, null, null, null, null);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.UserId);
    }

    [Fact]
    public void Empty_TenantId_Fails()
    {
        var command = new CreateFileCommand(Guid.NewGuid(), Guid.Empty, null, "test", true, null, null, null, null);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.TenantId);
    }
}
