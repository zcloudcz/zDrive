using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZDrive.PhotoService.Application.Commands.AddTag;
using Microsoft.Extensions.Options;
using ZDrive.PhotoService.Application.Options;
using ZDrive.PhotoService.Application.Queries.GetPhoto;
using ZDrive.PhotoService.Application.Queries.GetPhotoThumbnail;
using ZDrive.PhotoService.Application.Queries.GetTimeline;
using ZDrive.PhotoService.Application.Queries.SearchPhotos;
using ZDrive.Shared.Auth;

namespace ZDrive.Api.Controllers.Photos;

[ApiController]
[Route("api/v1/photos")]
[Authorize]
public class PhotosController : ControllerBase
{
    private readonly IMediator _mediator;
    private readonly PhotoThumbnailOptions _thumbnailOptions;

    public PhotosController(IMediator mediator, IOptions<PhotoThumbnailOptions> thumbnailOptions)
    {
        _mediator = mediator;
        _thumbnailOptions = thumbnailOptions.Value;
    }

    [HttpGet("timeline")]
    public async Task<IActionResult> GetTimeline(
        [FromQuery] DateTimeOffset? from,
        [FromQuery] DateTimeOffset? to,
        [FromQuery] int limit = 50,
        [FromQuery] int offset = 0,
        CancellationToken ct = default)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;
        var result = await _mediator.Send(new GetTimelineQuery(
            userId, tenantId, from?.UtcDateTime, to?.UtcDateTime, limit, offset), ct);
        return Ok(result);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;
        var result = await _mediator.Send(new GetPhotoQuery(userId, tenantId, id), ct);
        return Ok(result);
    }

    /// <summary>
    /// Generated WebP thumbnail (256 or 1024). 404 while the photo is not
    /// processed yet, is hidden, or its format cannot be decoded here.
    /// </summary>
    [HttpGet("{id:guid}/thumbnail/{size:int}")]
    [ProducesResponseType(typeof(FileStreamResult), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status304NotModified)]
    public async Task<IActionResult> GetThumbnail(Guid id, int size, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;
        var result = await _mediator.Send(new GetPhotoThumbnailQuery(
            userId, tenantId, id, size, Request.Headers.IfNoneMatch.ToString()), ct);

        Response.Headers.ETag = result.ETag;
        Response.Headers.CacheControl = $"private, max-age={_thumbnailOptions.CacheMaxAgeSeconds}";
        if (result.NotModified)
            return StatusCode(StatusCodes.Status304NotModified);

        return File(result.Content!, "image/webp");
    }

    [HttpGet("search")]
    public async Task<IActionResult> Search(
        [FromQuery] string q,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;
        var result = await _mediator.Send(new SearchPhotosQuery(
            userId, tenantId, q, page, pageSize), ct);
        return Ok(result);
    }

    [HttpPost("{id:guid}/tags")]
    public async Task<IActionResult> AddTag(Guid id, [FromBody] AddTagCommand command, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var enriched = command with { UserId = userId, TenantId = User.GetTenantId() ?? userId, PhotoId = id };
        var result = await _mediator.Send(enriched, ct);
        return Ok(result);
    }
}
