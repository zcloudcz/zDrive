using FluentValidation.TestHelper;
using Xunit;
using ZDrive.FileService.Application.Commands.CreateFileVersion;

namespace ZDrive.FileService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class CreateFileVersionCommandValidatorTests
{
    private readonly CreateFileVersionCommandValidator _validator = new();

    private static CreateFileVersionCommand Command(
        Guid? fileId = null,
        string blobVersionId = "blob-v1",
        long sizeBytes = 1024,
        string? manifestHash = "abc123",
        string? comment = "Initial version") =>
        new(
            TenantId: Guid.NewGuid(),
            UserId: Guid.NewGuid(),
            FileId: fileId ?? Guid.NewGuid(),
            BlobVersionId: blobVersionId,
            SizeBytes: sizeBytes,
            ManifestHash: manifestHash,
            Comment: comment);

    [Fact]
    public void Valid_Command_Passes()
    {
        var result = _validator.TestValidate(Command());
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_FileId_Fails()
    {
        var result = _validator.TestValidate(Command(fileId: Guid.Empty));
        result.ShouldHaveValidationErrorFor(x => x.FileId);
    }

    [Fact]
    public void Empty_BlobVersionId_Fails()
    {
        var result = _validator.TestValidate(Command(blobVersionId: ""));
        result.ShouldHaveValidationErrorFor(x => x.BlobVersionId);
    }

    [Fact]
    public void Negative_SizeBytes_Fails()
    {
        var result = _validator.TestValidate(Command(sizeBytes: -1));
        result.ShouldHaveValidationErrorFor(x => x.SizeBytes);
    }

    [Fact]
    public void Comment_Too_Long_Fails()
    {
        var result = _validator.TestValidate(Command(comment: new string('a', 1025)));
        result.ShouldHaveValidationErrorFor(x => x.Comment);
    }
}
