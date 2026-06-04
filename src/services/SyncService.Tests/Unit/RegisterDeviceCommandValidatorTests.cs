using FluentValidation.TestHelper;
using Xunit;
using ZDrive.SyncService.Application.Commands.RegisterDevice;
using ZDrive.SyncService.Domain.Enums;

namespace ZDrive.SyncService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class RegisterDeviceCommandValidatorTests
{
    private readonly RegisterDeviceCommandValidator _validator = new();

    [Theory]
    [InlineData("My Laptop", DevicePlatform.Windows)]
    [InlineData("iPhone 15", DevicePlatform.iOS)]
    [InlineData("Chrome Browser", DevicePlatform.Web)]
    public void Valid_Command_Passes(string name, DevicePlatform platform)
    {
        var command = new RegisterDeviceCommand(Guid.NewGuid(), name, platform);
        var result = _validator.TestValidate(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Empty_UserId_Fails()
    {
        var command = new RegisterDeviceCommand(Guid.Empty, "Device", DevicePlatform.Windows);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.UserId);
    }

    [Theory]
    [InlineData("")]
    [InlineData(null)]
    public void Empty_Name_Fails(string? name)
    {
        var command = new RegisterDeviceCommand(Guid.NewGuid(), name!, DevicePlatform.Windows);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Name);
    }

    [Fact]
    public void Name_ExceedsMaxLength_Fails()
    {
        var command = new RegisterDeviceCommand(Guid.NewGuid(), new string('a', 257), DevicePlatform.Windows);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Name);
    }

    [Fact]
    public void Invalid_Platform_Fails()
    {
        var command = new RegisterDeviceCommand(Guid.NewGuid(), "Device", (DevicePlatform)99);
        var result = _validator.TestValidate(command);
        result.ShouldHaveValidationErrorFor(x => x.Platform);
    }
}
