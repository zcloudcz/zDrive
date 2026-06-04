using FluentAssertions;
using MediatR;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZDrive.NotificationService.Application.Commands.SendNotification;
using ZDrive.NotificationService.Application.DTOs;
using ZDrive.NotificationService.Domain.Enums;

namespace ZDrive.NotificationService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class SignalRTests : IClassFixture<NotificationServiceFactory>
{
    private readonly NotificationServiceFactory _factory;

    public SignalRTests(NotificationServiceFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task SignalRConnection_ReceivesPushedNotification()
    {
        var userId = Guid.NewGuid();
        var token = _factory.GenerateTestToken(userId);

        // Create SignalR connection using the test server
        var server = _factory.Server;
        var hubConnection = new HubConnectionBuilder()
            .WithUrl(
                $"{server.BaseAddress}hubs/sync?access_token={token}",
                options =>
                {
                    options.HttpMessageHandlerFactory = _ => server.CreateHandler();
                })
            .Build();

        NotificationDto? receivedNotification = null;
        var receivedEvent = new TaskCompletionSource<NotificationDto>();

        hubConnection.On<NotificationDto>("ReceiveNotification", notification =>
        {
            receivedNotification = notification;
            receivedEvent.TrySetResult(notification);
        });

        await hubConnection.StartAsync();
        hubConnection.State.Should().Be(HubConnectionState.Connected);

        // Send a notification via MediatR
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();
        var sent = await mediator.Send(new SendNotificationCommand(
            userId, NotificationType.FileChanged, "Real-time test", "This should arrive via SignalR"));

        // Wait for the notification (with timeout)
        var completed = await Task.WhenAny(receivedEvent.Task, Task.Delay(TimeSpan.FromSeconds(10)));
        completed.Should().Be(receivedEvent.Task, "notification should be received within timeout");

        receivedNotification.Should().NotBeNull();
        receivedNotification!.Id.Should().Be(sent.Id);
        receivedNotification.Title.Should().Be("Real-time test");
        receivedNotification.Type.Should().Be("FileChanged");

        await hubConnection.DisposeAsync();
    }

    [Fact]
    public async Task SignalRConnection_FileChangedEvent_Received()
    {
        var userId = Guid.NewGuid();
        var token = _factory.GenerateTestToken(userId);

        var server = _factory.Server;
        var hubConnection = new HubConnectionBuilder()
            .WithUrl(
                $"{server.BaseAddress}hubs/sync?access_token={token}",
                options =>
                {
                    options.HttpMessageHandlerFactory = _ => server.CreateHandler();
                })
            .Build();

        FileChangeDto? receivedFileChange = null;
        var receivedEvent = new TaskCompletionSource<FileChangeDto>();

        hubConnection.On<FileChangeDto>("FileChanged", fileChange =>
        {
            receivedFileChange = fileChange;
            receivedEvent.TrySetResult(fileChange);
        });

        await hubConnection.StartAsync();

        // Broadcast a file change via MediatR
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();
        await mediator.Send(new Application.Commands.BroadcastFileChange.BroadcastFileChangeCommand(
            userId, Guid.NewGuid(), "Modified", "report.xlsx"));

        var completed = await Task.WhenAny(receivedEvent.Task, Task.Delay(TimeSpan.FromSeconds(10)));
        completed.Should().Be(receivedEvent.Task, "file change should be received within timeout");

        receivedFileChange.Should().NotBeNull();
        receivedFileChange!.FileName.Should().Be("report.xlsx");
        receivedFileChange.ChangeType.Should().Be("Modified");

        await hubConnection.DisposeAsync();
    }
}
