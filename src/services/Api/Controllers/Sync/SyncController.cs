using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZDrive.SyncService.Application.Commands.HeartbeatDevice;
using ZDrive.SyncService.Application.Commands.PushChanges;
using ZDrive.SyncService.Application.Commands.RegisterDevice;
using ZDrive.SyncService.Application.Commands.ResolveConflict;
using ZDrive.SyncService.Application.Commands.UnregisterDevice;
using ZDrive.SyncService.Application.DTOs;
using ZDrive.SyncService.Application.Queries.GetConflicts;
using ZDrive.SyncService.Application.Queries.ListDevices;
using ZDrive.SyncService.Application.Queries.PullChanges;
using ZDrive.SyncService.Domain.Enums;
using ZDrive.Shared.Auth;
using ZDrive.Shared.DTOs;

namespace ZDrive.Api.Controllers.Sync;

[ApiController]
[Route("api/v1/sync")]
[Authorize]
public sealed class SyncController : ControllerBase
{
    private readonly IMediator _mediator;

    public SyncController(IMediator mediator) => _mediator = mediator;

    [HttpPost("devices")]
    [ProducesResponseType(typeof(ApiResponse<DeviceDto>), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> RegisterDevice([FromBody] RegisterDeviceRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var command = new RegisterDeviceCommand(userId, request.Name, request.Platform);
        var result = await _mediator.Send(command, ct);
        return StatusCode(StatusCodes.Status201Created, ApiResponse<DeviceDto>.Ok(result));
    }

    [HttpDelete("devices/{id:guid}")]
    [ProducesResponseType(typeof(ApiResponse<bool>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> UnregisterDevice(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(new UnregisterDeviceCommand(userId, id), ct);
        return Ok(ApiResponse<bool>.Ok(result));
    }

    [HttpPost("devices/{id:guid}/heartbeat")]
    [ProducesResponseType(typeof(ApiResponse<bool>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> HeartbeatDevice(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(new HeartbeatDeviceCommand(userId, id), ct);
        return Ok(ApiResponse<bool>.Ok(result));
    }

    [HttpGet("devices")]
    [ProducesResponseType(typeof(ApiResponse<List<DeviceDto>>), StatusCodes.Status200OK)]
    public async Task<IActionResult> ListDevices(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(new ListDevicesQuery(userId), ct);
        return Ok(ApiResponse<List<DeviceDto>>.Ok(result));
    }

    [HttpPost("pull")]
    [ProducesResponseType(typeof(ApiResponse<PullResultDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> PullChanges([FromBody] PullChangesRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(new PullChangesQuery(userId, request.DeviceId, request.Cursor), ct);
        return Ok(ApiResponse<PullResultDto>.Ok(result));
    }

    [HttpPost("push")]
    [ProducesResponseType(typeof(ApiResponse<PushResultDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> PushChanges([FromBody] PushChangesRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var events = request.Events.Select(e => new PushEventItem(e.FileId, e.EventType, e.Metadata)).ToList();
        var result = await _mediator.Send(new PushChangesCommand(userId, request.DeviceId, events, request.BaseCursor), ct);
        return Ok(ApiResponse<PushResultDto>.Ok(result));
    }

    [HttpGet("conflicts")]
    [ProducesResponseType(typeof(ApiResponse<List<SyncConflictDto>>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetConflicts(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(new GetConflictsQuery(userId), ct);
        return Ok(ApiResponse<List<SyncConflictDto>>.Ok(result));
    }

    [HttpPost("conflicts/{id:guid}/resolve")]
    [ProducesResponseType(typeof(ApiResponse<bool>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> ResolveConflict(Guid id, [FromBody] ResolveConflictRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(new ResolveConflictCommand(userId, id, request.Resolution), ct);
        return Ok(ApiResponse<bool>.Ok(result));
    }
}

public sealed record RegisterDeviceRequest(string Name, DevicePlatform Platform);

public sealed record PullChangesRequest(Guid DeviceId, long Cursor);

public sealed record PushChangesRequest(Guid DeviceId, List<PushEventItemRequest> Events, long? BaseCursor = null);

public sealed record PushEventItemRequest(Guid FileId, SyncEventType EventType, string? Metadata);

public sealed record ResolveConflictRequest(ConflictResolution Resolution);
