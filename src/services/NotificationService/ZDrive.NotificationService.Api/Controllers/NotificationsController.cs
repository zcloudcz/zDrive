using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZDrive.NotificationService.Application.Commands.MarkAllRead;
using ZDrive.NotificationService.Application.Commands.MarkRead;
using ZDrive.NotificationService.Application.Commands.SendNotification;
using ZDrive.NotificationService.Application.Commands.UpdatePreference;
using ZDrive.NotificationService.Application.DTOs;
using ZDrive.NotificationService.Application.Queries.GetNotifications;
using ZDrive.NotificationService.Application.Queries.GetPreferences;
using ZDrive.NotificationService.Domain.Enums;
using ZDrive.Shared.Auth;
using ZDrive.Shared.DTOs;

namespace ZDrive.NotificationService.Api.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[Authorize]
public sealed class NotificationsController : ControllerBase
{
    private readonly IMediator _mediator;

    public NotificationsController(IMediator mediator) => _mediator = mediator;

    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<PagedResult<NotificationDto>>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetNotifications(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] bool? unreadOnly = null,
        CancellationToken ct = default)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(
            new GetNotificationsQuery(userId, page, pageSize, unreadOnly), ct);
        return Ok(ApiResponse<PagedResult<NotificationDto>>.Ok(result));
    }

    [HttpPost("{id:guid}/read")]
    [ProducesResponseType(typeof(ApiResponse<bool>), StatusCodes.Status200OK)]
    public async Task<IActionResult> MarkRead(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(new MarkReadCommand(userId, id), ct);
        return Ok(ApiResponse<bool>.Ok(result));
    }

    [HttpPost("read-all")]
    [ProducesResponseType(typeof(ApiResponse<int>), StatusCodes.Status200OK)]
    public async Task<IActionResult> MarkAllRead(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(new MarkAllReadCommand(userId), ct);
        return Ok(ApiResponse<int>.Ok(result));
    }

    [HttpGet("preferences")]
    [ProducesResponseType(typeof(ApiResponse<List<NotificationPreferenceDto>>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetPreferences(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(new GetPreferencesQuery(userId), ct);
        return Ok(ApiResponse<List<NotificationPreferenceDto>>.Ok(result));
    }

    [HttpPut("preferences")]
    [ProducesResponseType(typeof(ApiResponse<NotificationPreferenceDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> UpdatePreference(
        [FromBody] UpdatePreferenceRequest request,
        CancellationToken ct)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(
            new UpdatePreferenceCommand(userId, request.Channel, request.Type, request.Enabled), ct);
        return Ok(ApiResponse<NotificationPreferenceDto>.Ok(result));
    }
}

public sealed record UpdatePreferenceRequest(
    NotificationChannel Channel,
    NotificationType Type,
    bool Enabled);
