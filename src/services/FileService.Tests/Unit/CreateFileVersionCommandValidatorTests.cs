using FluentValidation.TestHelper;
using Xunit;
using ZDrive.FileService.Application.Commands.CreateFileVersion;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class CreateFileVersionCommandValidatorTests
{
    private readonly CreateFileVersionCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var command = new CreateFileVersionCommand(Guid.NewGuid(), "blob-v1", 1024, "abc123", Guid.NewGuid(), "Initial version");
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_FileId_Fails()
    {
        var command = new CreateFileVersionCommand(Guid.Empty, "blob-v1", 1024, null, Guid.NewGuid(), null);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.FileId);
    }

    [Fact]
    public void Empty_BlobVersionId_Fails()
    {
        var command = new CreateFileVersionCommand(Guid.NewGuid(), "", 1024, null, Guid.NewGuid(), null);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.BlobVersionId);
    }

    [Fact]
    public void Negative_SizeBytes_Fails()
    {
        var command = new CreateFileVersionCommand(Guid.NewGuid(), "blob-v1", -1, null, Guid.NewGuid(), null);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.SizeBytes);
    }

    [Fact]
    public void Comment_Too_Long_Fails()
    {
        var command = new CreateFileVersionCommand(Guid.NewGuid(), "blob-v1", 1024, null, Guid.NewGuid(), new string('a', 1025));
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Comment);
    }
}
