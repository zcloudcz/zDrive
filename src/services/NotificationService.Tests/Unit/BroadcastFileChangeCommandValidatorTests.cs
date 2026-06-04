using FluentValidation.TestHelper;
using Xunit;
using ZDrive.NotificationService.Application.Commands.BroadcastFileChange;

namespace ZDrive.NotificationService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class BroadcastFileChangeCommandValidatorTests
{
    private readonly BroadcastFileChangeCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var command = new BroadcastFileChangeCommand(
            Guid.NewGuid(), Guid.NewGuid(), "Modified", "document.pdf");
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_UserId_Fails()
    {
        var command = new BroadcastFileChangeCommand(
            Guid.Empty, Guid.NewGuid(), "Modified", "document.pdf");
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.UserId);
    }

    [Fact]
    public void Empty_FileId_Fails()
    {
        var command = new BroadcastFileChangeCommand(
            Guid.NewGuid(), Guid.Empty, "Modified", "document.pdf");
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.FileId);
    }

    [Fact]
    public void Empty_ChangeType_Fails()
    {
        var command = new BroadcastFileChangeCommand(
            Guid.NewGuid(), Guid.NewGuid(), "", "document.pdf");
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.ChangeType);
    }

    [Fact]
    public void Empty_FileName_Fails()
    {
        var command = new BroadcastFileChangeCommand(
            Guid.NewGuid(), Guid.NewGuid(), "Modified", "");
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.FileName);
    }
}
