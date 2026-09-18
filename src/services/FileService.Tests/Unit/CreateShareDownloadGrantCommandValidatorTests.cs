using FluentValidation.TestHelper;
using Xunit;
using ZDrive.FileService.Application.Commands.CreateShareDownloadGrant;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class CreateShareDownloadGrantCommandValidatorTests
{
    private readonly CreateShareDownloadGrantCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var result = _validator.TestValidate(new CreateShareDownloadGrantCommand("token123", Guid.NewGuid()));
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void EmptyLinkToken_Fails()
    {
        var result = _validator.TestValidate(new CreateShareDownloadGrantCommand("", Guid.NewGuid()));
        result.ShouldHaveValidationErrorFor(x => x.LinkToken);
    }

    [Fact]
    public void EmptyFileId_Fails()
    {
        var result = _validator.TestValidate(new CreateShareDownloadGrantCommand("token123", Guid.Empty));
        result.ShouldHaveValidationErrorFor(x => x.FileId);
    }
}
