using FluentValidation.TestHelper;
using Xunit;
using ZDrive.NotificationService.Application.Commands.SendNotification;
using ZDrive.NotificationService.Domain.Enums;

namespace ZDrive.NotificationService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class SendNotificationCommandValidatorTests
{
    private readonly SendNotificationCommandValidator _validator = new();

    [Fact]
    public void Valid_Command_Passes()
    {
        var command = new SendNotificationCommand(
            Guid.NewGuid(),
            NotificationType.FileChanged,
            "File updated",
            "document.pdf was modified");
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_UserId_Fails()
    {
        var command = new SendNotificationCommand(
            Guid.Empty,
            NotificationType.FileChanged,
            "Title",
            "Body");
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.UserId);
    }

    [Fact]
    public void Empty_Title_Fails()
    {
        var command = new SendNotificationCommand(
            Guid.NewGuid(),
            NotificationType.FileChanged,
            "",
            "Body");
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Title);
    }

    [Fact]
    public void Empty_Body_Fails()
    {
        var command = new SendNotificationCommand(
            Guid.NewGuid(),
            NotificationType.FileChanged,
            "Title",
            "");
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Body);
    }

    [Fact]
    public void Title_Over500_Fails()
    {
        var command = new SendNotificationCommand(
            Guid.NewGuid(),
            NotificationType.FileChanged,
            new string('x', 501),
            "Body");
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Title);
    }

    [Fact]
    public void Body_Over4000_Fails()
    {
        var command = new SendNotificationCommand(
            Guid.NewGuid(),
            NotificationType.FileChanged,
            "Title",
            new string('x', 4001));
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Body);
    }

    [Fact]
    public void Data_Over8000_Fails()
    {
        var command = new SendNotificationCommand(
            Guid.NewGuid(),
            NotificationType.FileChanged,
            "Title",
            "Body",
            new string('x', 8001));
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Data);
    }

    [Fact]
    public void Null_Data_Passes()
    {
        var command = new SendNotificationCommand(
            Guid.NewGuid(),
            NotificationType.FileShared,
            "Title",
            "Body",
            null);
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }
}
