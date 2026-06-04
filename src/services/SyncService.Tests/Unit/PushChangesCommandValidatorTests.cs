using FluentValidation.TestHelper;
using Xunit;
using ZDrive.SyncService.Application.Commands.PushChanges;
using ZDrive.SyncService.Domain.Enums;

namespace ZDrive.SyncService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class PushChangesCommandValidatorTests
{
    private readonly PushChangesCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var command = new PushChangesCommand(
            Guid.NewGuid(),
            Guid.NewGuid(),
            [new PushEventItem(Guid.NewGuid(), SyncEventType.Create, null)]);

        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_UserId_Fails()
    {
        var command = new PushChangesCommand(
            Guid.Empty,
            Guid.NewGuid(),
            [new PushEventItem(Guid.NewGuid(), SyncEventType.Create, null)]);

        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.UserId);
    }

    [Fact]
    public void Empty_DeviceId_Fails()
    {
        var command = new PushChangesCommand(
            Guid.NewGuid(),
            Guid.Empty,
            [new PushEventItem(Guid.NewGuid(), SyncEventType.Create, null)]);

        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.DeviceId);
    }

    [Fact]
    public void Event_With_Empty_FileId_Fails()
    {
        var command = new PushChangesCommand(
            Guid.NewGuid(),
            Guid.NewGuid(),
            [new PushEventItem(Guid.Empty, SyncEventType.Create, null)]);

        var result = _validator.TestValidate(command);
        result.ShouldHaveAnyValidationError();
    }

    [Fact]
    public void Event_With_Invalid_EventType_Fails()
    {
        var command = new PushChangesCommand(
            Guid.NewGuid(),
            Guid.NewGuid(),
            [new PushEventItem(Guid.NewGuid(), (SyncEventType)99, null)]);

        var result = _validator.TestValidate(command);
        result.ShouldHaveAnyValidationError();
    }
}
