using FluentAssertions;
using FluentValidation.TestHelper;
using Xunit;
using ZDrive.StorageService.Application.Commands.InitUpload;

namespace ZDrive.StorageService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class InitUploadCommandValidatorTests
{
    private readonly InitUploadCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var command = new InitUploadCommand(
            Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "test-file.txt", 3);
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_UserId_Fails()
    {
        var command = new InitUploadCommand(
            Guid.Empty, Guid.NewGuid(), Guid.NewGuid(), "test-file.txt", 3);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.UserId);
    }

    [Fact]
    public void Empty_TenantId_Fails()
    {
        var command = new InitUploadCommand(
            Guid.NewGuid(), Guid.Empty, Guid.NewGuid(), "test-file.txt", 3);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.TenantId);
    }

    [Fact]
    public void Empty_FileName_Fails()
    {
        var command = new InitUploadCommand(
            Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "", 3);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.FileName);
    }

    [Fact]
    public void Zero_TotalChunks_Fails()
    {
        var command = new InitUploadCommand(
            Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "test.txt", 0);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.TotalChunks);
    }

    [Fact]
    public void Negative_TotalChunks_Fails()
    {
        var command = new InitUploadCommand(
            Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "test.txt", -1);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.TotalChunks);
    }

    [Fact]
    public void TotalChunks_ExceedsMax_Fails()
    {
        var command = new InitUploadCommand(
            Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), "test.txt", 50_001);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.TotalChunks);
    }
}
