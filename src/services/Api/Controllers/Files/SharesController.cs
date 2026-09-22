using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZDrive.FileService.Application.Commands.CreateShare;
using ZDrive.FileService.Application.Commands.CreateShareDownloadGrant;
using ZDrive.FileService.Application.Commands.CreateShareFileVersion;
using ZDrive.FileService.Application.Commands.CreateSharedFolder;
using ZDrive.FileService.Application.Commands.CreateShareUploadGrant;
using ZDrive.FileService.Application.Commands.DeleteSharedItem;
using ZDrive.FileService.Application.Commands.RevokeShare;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Queries.GetShareByToken;
using ZDrive.FileService.Application.Queries.GetShareInfo;
using ZDrive.FileService.Application.Queries.ListSharedChildren;
using ZDrive.FileService.Domain.Enums;
using ZDrive.Shared.Auth;
using ZDrive.Shared.DTOs;
using ZDrive.Shared.Http;

namespace ZDrive.Api.Controllers.Files;

[ApiController]
[Route("api/v1/shares")]
public sealed class SharesController : ControllerBase
{
    private readonly IMediator _mediator;

    public SharesController(IMediator mediator) => _mediator = mediator;

    [HttpPost]
    [Authorize]
    [ProducesResponseType(typeof(ApiResponse<ShareDto>), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> CreateShare([FromBody] CreateShareRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var command = new CreateShareCommand(
            userId, request.FileId, request.SharedWith, request.Permission,
            request.Password, request.ExpiresAt, request.AllowDelete);
        var result = await _mediator.Send(command, ct);
        return CreatedAtAction(nameof(GetShareByToken), new { token = result.LinkToken }, ApiResponse<ShareDto>.Ok(result));
    }

    [HttpDelete("{id:guid}")]
    [Authorize]
    [ProducesResponseType(typeof(ApiResponse<bool>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> RevokeShare(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var result = await _mediator.Send(new RevokeShareCommand(userId, id), ct);
        return Ok(ApiResponse<bool>.Ok(result));
    }

    [HttpGet("link/{token}")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ApiResponse<SharedFileDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetShareByToken(string token, CancellationToken ct)
    {
        // Set before the mediator call can throw, so it lands on the 404 too
        // — see ShareResponseHeaderExtensions. The URL carries the token
        // here (not a header), but no-store costs nothing and keeps every
        // shares/link/* response consistently uncached.
        Response.SetPublicShareCacheHeaders();

        var result = await _mediator.Send(new GetShareByTokenQuery(token), ct);
        return Ok(ApiResponse<SharedFileDto>.Ok(result));
    }

    [HttpGet("link/{token}/children")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ApiResponse<List<FileDto>>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetSharedChildren(string token, [FromQuery] Guid? folderId, CancellationToken ct)
    {
        Response.SetPublicShareCacheHeaders();

        var result = await _mediator.Send(new ListSharedChildrenQuery(token, folderId), ct);
        return Ok(ApiResponse<List<FileDto>>.Ok(result));
    }

    [HttpPost("link/{token}/download-grant")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ApiResponse<ShareDownloadGrantDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> CreateShareDownloadGrant(
        string token, [FromBody] CreateShareDownloadGrantRequest request, CancellationToken ct)
    {
        // The response body here IS a credential (the grant), so this is the
        // one of the three where no-store matters most.
        Response.SetPublicShareCacheHeaders();

        var result = await _mediator.Send(new CreateShareDownloadGrantCommand(token, request.FileId), ct);
        return Ok(ApiResponse<ShareDownloadGrantDto>.Ok(result));
    }

    [HttpGet("link/{token}/info")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ApiResponse<ShareInfoDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetShareInfo(string token, CancellationToken ct)
    {
        Response.SetPublicShareCacheHeaders();

        var result = await _mediator.Send(new GetShareInfoQuery(token), ct);
        return Ok(ApiResponse<ShareInfoDto>.Ok(result));
    }

    [HttpPost("link/{token}/folders")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ApiResponse<FileDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> CreateSharedFolder(
        string token, [FromBody] CreateSharedFolderRequest request, CancellationToken ct)
    {
        Response.SetPublicShareCacheHeaders();

        var result = await _mediator.Send(new CreateSharedFolderCommand(token, request.ParentId, request.Name), ct);
        return Ok(ApiResponse<FileDto>.Ok(result));
    }

    [HttpPost("link/{token}/upload-grant")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ApiResponse<ShareUploadGrantResultDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status413PayloadTooLarge)]
    public async Task<IActionResult> CreateShareUploadGrant(
        string token, [FromBody] CreateShareUploadGrantRequest request, CancellationToken ct)
    {
        // The response body here IS a credential (the grant), same as the download-grant endpoint.
        Response.SetPublicShareCacheHeaders();

        var command = new CreateShareUploadGrantCommand(
            token, request.ParentId, request.FileName, request.SizeBytes, request.Overwrite);
        var result = await _mediator.Send(command, ct);
        return Ok(ApiResponse<ShareUploadGrantResultDto>.Ok(result));
    }

    [HttpPost("link/{token}/files/{fileId:guid}/versions")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ApiResponse<FileDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status413PayloadTooLarge)]
    public async Task<IActionResult> CreateShareFileVersion(
        string token, Guid fileId, [FromBody] CreateShareFileVersionRequest request, CancellationToken ct)
    {
        Response.SetPublicShareCacheHeaders();

        var result = await _mediator.Send(new CreateShareFileVersionCommand(token, fileId, request.Receipt), ct);
        return Ok(ApiResponse<FileDto>.Ok(result));
    }

    [HttpDelete("link/{token}/items/{id:guid}")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ApiResponse<bool>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeleteSharedItem(string token, Guid id, CancellationToken ct)
    {
        Response.SetPublicShareCacheHeaders();

        var result = await _mediator.Send(new DeleteSharedItemCommand(token, id), ct);
        return Ok(ApiResponse<bool>.Ok(result));
    }
}

public sealed record CreateShareRequest(
    Guid FileId,
    Guid? SharedWith,
    Permission Permission,
    string? Password = null,
    DateTime? ExpiresAt = null,
    bool AllowDelete = false);

public sealed record CreateShareDownloadGrantRequest(Guid FileId);

public sealed record CreateSharedFolderRequest(Guid? ParentId, string Name);

public sealed record CreateShareUploadGrantRequest(Guid? ParentId, string? FileName, long SizeBytes, bool Overwrite);

public sealed record CreateShareFileVersionRequest(string Receipt);
