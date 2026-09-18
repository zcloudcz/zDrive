using FluentAssertions;
using FluentValidation.TestHelper;
using Xunit;
using ZDrive.StorageService.Application.Commands.UploadChunk;

namespace ZDrive.StorageService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class UploadChunkCommandValidatorTests
{
    private readonly UploadChunkCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        using var stream = new MemoryStream([1, 2, 3]);
        var command = new UploadChunkCommand(Guid.NewGuid(), 0, "abc123", stream, Guid.NewGuid(), Guid.NewGuid());
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_SessionId_Fails()
    {
        using var stream = new MemoryStream([1, 2, 3]);
        var command = new UploadChunkCommand(Guid.Empty, 0, "abc123", stream, Guid.NewGuid(), Guid.NewGuid());
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.SessionId);
    }

    [Fact]
    public void Empty_ChunkHash_Fails()
    {
        using var stream = new MemoryStream([1, 2, 3]);
        var command = new UploadChunkCommand(Guid.NewGuid(), 0, "", stream, Guid.NewGuid(), Guid.NewGuid());
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.ChunkHash);
    }

    [Fact]
    public void Negative_ChunkIndex_Fails()
    {
        using var stream = new MemoryStream([1, 2, 3]);
        var command = new UploadChunkCommand(Guid.NewGuid(), -1, "abc123", stream, Guid.NewGuid(), Guid.NewGuid());
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.ChunkIndex);
    }
}
