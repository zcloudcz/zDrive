using FluentValidation.TestHelper;
using Xunit;
using ZDrive.StorageService.Application.Commands.CompleteUpload;

namespace ZDrive.StorageService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class CompleteUploadCommandValidatorTests
{
    private readonly CompleteUploadCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var command = new CompleteUploadCommand(Guid.NewGuid());
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_SessionId_Fails()
    {
        var command = new CompleteUploadCommand(Guid.Empty);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.SessionId);
    }
}
