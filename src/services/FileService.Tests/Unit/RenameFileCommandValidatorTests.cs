using FluentAssertions;
using FluentValidation.TestHelper;
using Xunit;
using ZDrive.FileService.Application.Commands.RenameFile;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class RenameFileCommandValidatorTests
{
    private readonly RenameFileCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var command = new RenameFileCommand(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "NewName.txt");
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_NewName_Fails()
    {
        var command = new RenameFileCommand(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "");
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.NewName);
    }

    [Fact]
    public void Empty_FileId_Fails()
    {
        var command = new RenameFileCommand(Guid.NewGuid(), Guid.NewGuid(), Guid.Empty, "NewName.txt");
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.FileId);
    }
}
