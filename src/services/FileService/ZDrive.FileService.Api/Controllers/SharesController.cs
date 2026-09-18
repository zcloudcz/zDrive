using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZDrive.FileService.Application.Commands.CreateShare;
using ZDrive.FileService.Application.Commands.CreateShareDownloadGrant;
using ZDrive.FileService.Application.Commands.RevokeShare;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Queries.GetShareByToken;
using ZDrive.FileService.Application.Queries.ListSharedChildren;
using ZDrive.FileService.Domain.Enums;
using ZDrive.Shared.Auth;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Api.Controllers;

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
            request.Password, request.ExpiresAt);
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
        var result = await _mediator.Send(new GetShareByTokenQuery(token), ct);
        return Ok(ApiResponse<SharedFileDto>.Ok(result));
    }

    [HttpGet("link/{token}/children")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ApiResponse<List<FileDto>>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetSharedChildren(string token, [FromQuery] Guid? folderId, CancellationToken ct)
    {
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
        var result = await _mediator.Send(new CreateShareDownloadGrantCommand(token, request.FileId), ct);
        return Ok(ApiResponse<ShareDownloadGrantDto>.Ok(result));
    }
}

public sealed record CreateShareRequest(
    Guid FileId,
    Guid? SharedWith,
    Permission Permission,
    string? Password = null,
    DateTime? ExpiresAt = null);

public sealed record CreateShareDownloadGrantRequest(Guid FileId);
