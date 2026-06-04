using FluentValidation.TestHelper;
using Xunit;
using ZDrive.NotificationService.Application.Commands.UpdatePreference;
using ZDrive.NotificationService.Domain.Enums;

namespace ZDrive.NotificationService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class UpdatePreferenceCommandValidatorTests
{
    private readonly UpdatePreferenceCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var command = new UpdatePreferenceCommand(
            Guid.NewGuid(), NotificationChannel.InApp, NotificationType.FileChanged, true);
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_UserId_Fails()
    {
        var command = new UpdatePreferenceCommand(
            Guid.Empty, NotificationChannel.Push, NotificationType.FileShared, false);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.UserId);
    }

    [Theory]
    [InlineData(NotificationChannel.Push)]
    [InlineData(NotificationChannel.Email)]
    [InlineData(NotificationChannel.InApp)]
    public void All_Channels_Pass(NotificationChannel channel)
    {
        var command = new UpdatePreferenceCommand(
            Guid.NewGuid(), channel, NotificationType.FileChanged, true);
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Theory]
    [InlineData(NotificationType.FileChanged)]
    [InlineData(NotificationType.FileShared)]
    [InlineData(NotificationType.PhotoUploaded)]
    [InlineData(NotificationType.MemoryCreated)]
    [InlineData(NotificationType.SyncConflict)]
    public void All_Types_Pass(NotificationType type)
    {
        var command = new UpdatePreferenceCommand(
            Guid.NewGuid(), NotificationChannel.InApp, type, false);
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }
}
