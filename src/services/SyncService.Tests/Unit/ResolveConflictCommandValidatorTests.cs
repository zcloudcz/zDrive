using FluentValidation.TestHelper;
using Xunit;
using ZDrive.SyncService.Application.Commands.ResolveConflict;
using ZDrive.SyncService.Domain.Enums;

namespace ZDrive.SyncService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class ResolveConflictCommandValidatorTests
{
    private readonly ResolveConflictCommandValidator _validator = new();

    [Theory]
    [InlineData(ConflictResolution.KeepLocal)]
    [InlineData(ConflictResolution.KeepRemote)]
    [InlineData(ConflictResolution.KeepBoth)]
    public void Valid_Command_Passes(ConflictResolution resolution)
    {
        var command = new ResolveConflictCommand(Guid.NewGuid(), Guid.NewGuid(), resolution);
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_UserId_Fails()
    {
        var command = new ResolveConflictCommand(Guid.Empty, Guid.NewGuid(), ConflictResolution.KeepLocal);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.UserId);
    }

    [Fact]
    public void Empty_ConflictId_Fails()
    {
        var command = new ResolveConflictCommand(Guid.NewGuid(), Guid.Empty, ConflictResolution.KeepLocal);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.ConflictId);
    }

    [Fact]
    public void Invalid_Resolution_Fails()
    {
        var command = new ResolveConflictCommand(Guid.NewGuid(), Guid.NewGuid(), (ConflictResolution)99);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Resolution);
    }
}
