using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using FluentAssertions;
using MediatR;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZDrive.NotificationService.Application.Commands.SendNotification;
using ZDrive.NotificationService.Application.DTOs;
using ZDrive.NotificationService.Domain.Enums;
using ZDrive.Shared.DTOs;

namespace ZDrive.NotificationService.Tests.Integration;

[Trait("Category", "Integration")]
public sealed class NotificationFlowTests : IClassFixture<NotificationServiceFactory>
{
    private readonly NotificationServiceFactory _factory;
    private readonly HttpClient _client;

    public NotificationFlowTests(NotificationServiceFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    private void Authenticate(Guid userId)
    {
        var token = _factory.GenerateTestToken(userId);
        _client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
    }

    [Fact]
    public async Task SendNotification_AppearsInGetList()
    {
        var userId = Guid.NewGuid();
        Authenticate(userId);

        // Send notification via MediatR (simulating internal service call)
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();
        var sent = await mediator.Send(new SendNotificationCommand(
            userId, NotificationType.FileChanged, "File updated", "document.pdf was modified"));

        sent.Should().NotBeNull();
        sent.Type.Should().Be("FileChanged");

        // Retrieve via API
        var response = await _client.GetAsync("/api/v1/notifications");
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var result = await response.Content.ReadFromJsonAsync<ApiResponse<PagedResult<NotificationDto>>>();
        result.Should().NotBeNull();
        result!.Success.Should().BeTrue();
        result.Data!.Items.Should().Contain(n => n.Id == sent.Id);
    }

    [Fact]
    public async Task MarkRead_ChangesIsRead()
    {
        var userId = Guid.NewGuid();
        Authenticate(userId);

        // Create a notification
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();
        var sent = await mediator.Send(new SendNotificationCommand(
            userId, NotificationType.FileShared, "File shared", "Someone shared a file with you"));

        sent.IsRead.Should().BeFalse();

        // Mark as read via API
        var markResponse = await _client.PostAsync($"/api/v1/notifications/{sent.Id}/read", null);
        markResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var markResult = await markResponse.Content.ReadFromJsonAsync<ApiResponse<bool>>();
        markResult!.Data.Should().BeTrue();

        // Verify it's now read
        var listResponse = await _client.GetAsync("/api/v1/notifications");
        var listResult = await listResponse.Content.ReadFromJsonAsync<ApiResponse<PagedResult<NotificationDto>>>();
        listResult!.Data!.Items.Should().Contain(n => n.Id == sent.Id && n.IsRead);
    }

    [Fact]
    public async Task MarkAllRead_AllUpdated()
    {
        var userId = Guid.NewGuid();
        Authenticate(userId);

        // Create multiple notifications
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();
        await mediator.Send(new SendNotificationCommand(
            userId, NotificationType.FileChanged, "Change 1", "Body 1"));
        await mediator.Send(new SendNotificationCommand(
            userId, NotificationType.FileChanged, "Change 2", "Body 2"));
        await mediator.Send(new SendNotificationCommand(
            userId, NotificationType.FileChanged, "Change 3", "Body 3"));

        // Mark all read
        var markAllResponse = await _client.PostAsync("/api/v1/notifications/read-all", null);
        markAllResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var markAllResult = await markAllResponse.Content.ReadFromJsonAsync<ApiResponse<int>>();
        markAllResult!.Data.Should().BeGreaterThanOrEqualTo(3);

        // Verify all are read
        var listResponse = await _client.GetAsync("/api/v1/notifications?unreadOnly=true");
        var listResult = await listResponse.Content.ReadFromJsonAsync<ApiResponse<PagedResult<NotificationDto>>>();
        listResult!.Data!.Items.Should().BeEmpty();
    }

    [Fact]
    public async Task PreferenceToggle_PersistsCorrectly()
    {
        var userId = Guid.NewGuid();
        Authenticate(userId);

        // Set a preference
        var updateResponse = await _client.PutAsJsonAsync("/api/v1/notifications/preferences", new
        {
            channel = "InApp",
            type = "FileChanged",
            enabled = false
        });
        updateResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var updateResult = await updateResponse.Content.ReadFromJsonAsync<ApiResponse<NotificationPreferenceDto>>();
        updateResult!.Data!.Enabled.Should().BeFalse();
        updateResult.Data.Channel.Should().Be("InApp");
        updateResult.Data.Type.Should().Be("FileChanged");

        // Get preferences
        var getResponse = await _client.GetAsync("/api/v1/notifications/preferences");
        getResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var getResult = await getResponse.Content.ReadFromJsonAsync<ApiResponse<List<NotificationPreferenceDto>>>();
        getResult!.Data.Should().Contain(p =>
            p.Channel == "InApp" && p.Type == "FileChanged" && !p.Enabled);

        // Toggle it back
        var toggleResponse = await _client.PutAsJsonAsync("/api/v1/notifications/preferences", new
        {
            channel = "InApp",
            type = "FileChanged",
            enabled = true
        });
        toggleResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var toggleResult = await toggleResponse.Content.ReadFromJsonAsync<ApiResponse<NotificationPreferenceDto>>();
        toggleResult!.Data!.Enabled.Should().BeTrue();
    }

    [Fact]
    public async Task GetNotifications_WithoutToken_Returns401()
    {
        var unauthClient = _factory.CreateClient();
        var response = await unauthClient.GetAsync("/api/v1/notifications");
        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task GetNotifications_Pagination_Works()
    {
        var userId = Guid.NewGuid();
        Authenticate(userId);

        // Create 5 notifications
        using var scope = _factory.Services.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();
        for (var i = 0; i < 5; i++)
        {
            await mediator.Send(new SendNotificationCommand(
                userId, NotificationType.FileChanged, $"Title {i}", $"Body {i}"));
        }

        // Get page 1 with size 2
        var response = await _client.GetAsync("/api/v1/notifications?page=1&pageSize=2");
        var result = await response.Content.ReadFromJsonAsync<ApiResponse<PagedResult<NotificationDto>>>();
        result!.Data!.Items.Should().HaveCount(2);
        result.Data.TotalCount.Should().Be(5);
        result.Data.HasNextPage.Should().BeTrue();

        // Get page 3 with size 2
        var response2 = await _client.GetAsync("/api/v1/notifications?page=3&pageSize=2");
        var result2 = await response2.Content.ReadFromJsonAsync<ApiResponse<PagedResult<NotificationDto>>>();
        result2!.Data!.Items.Should().HaveCount(1);
        result2.Data.HasNextPage.Should().BeFalse();
    }

    [Fact]
    public async Task MarkRead_NonExistentNotification_ReturnsFalse()
    {
        var userId = Guid.NewGuid();
        Authenticate(userId);

        var response = await _client.PostAsync($"/api/v1/notifications/{Guid.NewGuid()}/read", null);
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var result = await response.Content.ReadFromJsonAsync<ApiResponse<bool>>();
        result!.Data.Should().BeFalse();
    }
}
