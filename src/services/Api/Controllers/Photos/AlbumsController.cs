using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZDrive.PhotoService.Application.Commands.AddPhotosToAlbum;
using ZDrive.PhotoService.Application.Commands.CreateAlbum;
using ZDrive.PhotoService.Application.Commands.DeleteAlbum;
using ZDrive.PhotoService.Application.Commands.RemovePhotoFromAlbum;
using ZDrive.PhotoService.Application.Commands.UpdateAlbum;
using ZDrive.PhotoService.Application.Queries.GetAlbumPhotos;
using ZDrive.PhotoService.Application.Queries.GetAlbums;
using ZDrive.Shared.Auth;

namespace ZDrive.Api.Controllers.Photos;

[ApiController]
[Route("api/v1/albums")]
[Authorize]
public class AlbumsController : ControllerBase
{
    private readonly IMediator _mediator;

    public AlbumsController(IMediator mediator) => _mediator = mediator;

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateAlbumCommand command, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;
        var enriched = command with { UserId = userId, TenantId = tenantId };
        var result = await _mediator.Send(enriched, ct);
        return CreatedAtAction(nameof(GetPhotos), new { id = result.Id }, result);
    }

    [HttpGet]
    public async Task<IActionResult> GetAll(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;
        var result = await _mediator.Send(new GetAlbumsQuery(userId, tenantId), ct);
        return Ok(result);
    }

    [HttpGet("{id:guid}/photos")]
    public async Task<IActionResult> GetPhotos(Guid id, [FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken ct = default)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;
        var result = await _mediator.Send(new GetAlbumPhotosQuery(userId, tenantId, id, page, pageSize), ct);
        return Ok(result);
    }

    [HttpPost("{id:guid}/photos")]
    public async Task<IActionResult> AddPhotos(Guid id, [FromBody] AddPhotosToAlbumCommand command, CancellationToken ct)
    {
        var enriched = command with { UserId = User.GetUserId(), AlbumId = id };
        var result = await _mediator.Send(enriched, ct);
        return Ok(new { added = result });
    }

    [HttpDelete("{id:guid}/photos/{photoId:guid}")]
    public async Task<IActionResult> RemovePhoto(Guid id, Guid photoId, CancellationToken ct)
    {
        await _mediator.Send(new RemovePhotoFromAlbumCommand(User.GetUserId(), id, photoId), ct);
        return NoContent();
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateAlbumCommand command, CancellationToken ct)
    {
        var enriched = command with { UserId = User.GetUserId(), AlbumId = id };
        var result = await _mediator.Send(enriched, ct);
        return Ok(result);
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        await _mediator.Send(new DeleteAlbumCommand(User.GetUserId(), id), ct);
        return NoContent();
    }
}
