using FluentAssertions;
using Xunit;
using ZDrive.NotificationService.Domain.Entities;

namespace ZDrive.NotificationService.Tests.Unit;

[Trait("Category", "Unit")]
public sealed class ConnectionMappingTests
{
    [Fact]
    public void Add_SingleConnection_IsConnectedReturnsTrue()
    {
        var mapping = new ConnectionMapping();
        var userId = Guid.NewGuid();

        mapping.Add(userId, "conn-1");

        mapping.IsConnected(userId).Should().BeTrue();
        mapping.GetConnections(userId).Should().ContainSingle().Which.Should().Be("conn-1");
    }

    [Fact]
    public void Add_MultipleConnections_AllReturned()
    {
        var mapping = new ConnectionMapping();
        var userId = Guid.NewGuid();

        mapping.Add(userId, "conn-1");
        mapping.Add(userId, "conn-2");
        mapping.Add(userId, "conn-3");

        mapping.GetConnections(userId).Should().HaveCount(3);
        mapping.GetConnections(userId).Should().Contain(["conn-1", "conn-2", "conn-3"]);
    }

    [Fact]
    public void Remove_LastConnection_IsConnectedReturnsFalse()
    {
        var mapping = new ConnectionMapping();
        var userId = Guid.NewGuid();

        mapping.Add(userId, "conn-1");
        mapping.Remove(userId, "conn-1");

        mapping.IsConnected(userId).Should().BeFalse();
        mapping.GetConnections(userId).Should().BeEmpty();
    }

    [Fact]
    public void Remove_OneOfMultiple_OthersRemain()
    {
        var mapping = new ConnectionMapping();
        var userId = Guid.NewGuid();

        mapping.Add(userId, "conn-1");
        mapping.Add(userId, "conn-2");
        mapping.Remove(userId, "conn-1");

        mapping.IsConnected(userId).Should().BeTrue();
        mapping.GetConnections(userId).Should().ContainSingle().Which.Should().Be("conn-2");
    }

    [Fact]
    public void GetConnections_UnknownUser_ReturnsEmpty()
    {
        var mapping = new ConnectionMapping();

        mapping.GetConnections(Guid.NewGuid()).Should().BeEmpty();
    }

    [Fact]
    public void IsConnected_UnknownUser_ReturnsFalse()
    {
        var mapping = new ConnectionMapping();

        mapping.IsConnected(Guid.NewGuid()).Should().BeFalse();
    }

    [Fact]
    public void Remove_NonExistentConnection_NoError()
    {
        var mapping = new ConnectionMapping();
        var userId = Guid.NewGuid();

        // Should not throw
        mapping.Remove(userId, "conn-nonexistent");

        mapping.IsConnected(userId).Should().BeFalse();
    }

    [Fact]
    public void ConnectionCount_ReflectsAllUsersConnections()
    {
        var mapping = new ConnectionMapping();
        var user1 = Guid.NewGuid();
        var user2 = Guid.NewGuid();

        mapping.Add(user1, "conn-1");
        mapping.Add(user1, "conn-2");
        mapping.Add(user2, "conn-3");

        mapping.ConnectionCount.Should().Be(3);
    }

    [Fact]
    public void DifferentUsers_IndependentConnections()
    {
        var mapping = new ConnectionMapping();
        var user1 = Guid.NewGuid();
        var user2 = Guid.NewGuid();

        mapping.Add(user1, "conn-1");
        mapping.Add(user2, "conn-2");

        mapping.GetConnections(user1).Should().ContainSingle().Which.Should().Be("conn-1");
        mapping.GetConnections(user2).Should().ContainSingle().Which.Should().Be("conn-2");
    }
}
