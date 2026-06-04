using FluentValidation.TestHelper;
using Xunit;
using ZDrive.StorageService.Application.Commands.DeleteBlob;

namespace ZDrive.StorageService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class DeleteBlobCommandValidatorTests
{
    private readonly DeleteBlobCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var command = new DeleteBlobCommand(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_TenantId_Fails()
    {
        var command = new DeleteBlobCommand(Guid.Empty, Guid.NewGuid(), Guid.NewGuid());
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.TenantId);
    }

    [Fact]
    public void Empty_UserId_Fails()
    {
        var command = new DeleteBlobCommand(Guid.NewGuid(), Guid.Empty, Guid.NewGuid());
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.UserId);
    }

    [Fact]
    public void Empty_FileId_Fails()
    {
        var command = new DeleteBlobCommand(Guid.NewGuid(), Guid.NewGuid(), Guid.Empty);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.FileId);
    }
}
