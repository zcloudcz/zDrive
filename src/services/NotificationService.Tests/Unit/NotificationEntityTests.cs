using FluentAssertions;
using Xunit;
using ZDrive.NotificationService.Domain.Entities;
using ZDrive.NotificationService.Domain.Enums;

namespace ZDrive.NotificationService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class NotificationEntityTests
{
    [Fact]
    public void Notification_DefaultValues_AreCorrect()
    {
        var notification = new Notification
        {
            Id = Guid.NewGuid(),
            UserId = Guid.NewGuid(),
            Type = NotificationType.FileChanged,
            Title = "Test",
            Body = "Test body"
        };

        notification.IsRead.Should().BeFalse();
        notification.CreatedAt.Should().BeCloseTo(DateTime.UtcNow, TimeSpan.FromSeconds(5));
        notification.Data.Should().BeNull();
    }

    [Fact]
    public void NotificationPreference_DefaultValues_AreCorrect()
    {
        var preference = new NotificationPreference
        {
            Id = Guid.NewGuid(),
            UserId = Guid.NewGuid(),
            Channel = NotificationChannel.InApp,
            Type = NotificationType.FileShared
        };

        preference.Enabled.Should().BeTrue();
    }
}
