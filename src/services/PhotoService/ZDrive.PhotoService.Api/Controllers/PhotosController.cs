using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZDrive.PhotoService.Application.Commands.AddTag;
using ZDrive.PhotoService.Application.Commands.IngestPhoto;
using ZDrive.PhotoService.Application.Queries.GetPhoto;
using ZDrive.PhotoService.Application.Queries.GetTimeline;
using ZDrive.PhotoService.Application.Queries.SearchPhotos;
using ZDrive.Shared.Auth;

namespace ZDrive.PhotoService.Api.Controllers;

[ApiController]
[Route("api/v1/photos")]
[Authorize]
public class PhotosController : ControllerBase
{
    private readonly IMediator _mediator;

    public PhotosController(IMediator mediator) => _mediator = mediator;

    [HttpPost("ingest")]
    public async Task<IActionResult> Ingest([FromBody] IngestPhotoCommand command, CancellationToken ct)
    {
        var enriched = command with
        {
            UserId = User.GetUserId(),
            TenantId = User.GetTenantId()
        };
        var result = await _mediator.Send(enriched, ct);
        return CreatedAtAction(nameof(GetById), new { id = result.Id }, result);
    }

    [HttpGet("timeline")]
    public async Task<IActionResult> GetTimeline(
        [FromQuery] DateTimeOffset? from,
        [FromQuery] DateTimeOffset? to,
        [FromQuery] int limit = 50,
        [FromQuery] int offset = 0,
        CancellationToken ct = default)
    {
        var result = await _mediator.Send(new GetTimelineQuery(
            User.GetUserId(), User.GetTenantId(), from, to, limit, offset), ct);
        return Ok(result);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct)
    {
        var result = await _mediator.Send(new GetPhotoQuery(User.GetUserId(), User.GetTenantId(), id), ct);
        return Ok(result);
    }

    [HttpGet("search")]
    public async Task<IActionResult> Search(
        [FromQuery] string q,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var result = await _mediator.Send(new SearchPhotosQuery(
            User.GetUserId(), User.GetTenantId(), q, page, pageSize), ct);
        return Ok(result);
    }

    [HttpPost("{id:guid}/tags")]
    public async Task<IActionResult> AddTag(Guid id, [FromBody] AddTagCommand command, CancellationToken ct)
    {
        var enriched = command with { PhotoId = id };
        var result = await _mediator.Send(enriched, ct);
        return Ok(result);
    }
}
