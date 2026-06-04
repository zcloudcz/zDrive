using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZDrive.Shared.Auth;
using ZDrive.Shared.DTOs;
using ZDrive.StorageService.Application.Commands.CompleteUpload;
using ZDrive.StorageService.Application.Commands.DeleteBlob;
using ZDrive.StorageService.Application.Commands.InitUpload;
using ZDrive.StorageService.Application.Commands.UploadChunk;
using ZDrive.StorageService.Application.DTOs;
using ZDrive.StorageService.Application.Queries.GetChunkDownloadUrl;
using ZDrive.StorageService.Application.Queries.GetDownloadUrl;
using ZDrive.StorageService.Application.Queries.GetThumbnailUrl;

namespace ZDrive.StorageService.Api.Controllers;

[ApiController]
[Route("api/v1/storage")]
[Authorize]
public sealed class StorageController : ControllerBase
{
    private readonly IMediator _mediator;

    public StorageController(IMediator mediator) => _mediator = mediator;

    [HttpPost("upload/init")]
    [ProducesResponseType(typeof(ApiResponse<UploadSessionDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> InitUpload([FromBody] InitUploadRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;

        var command = new InitUploadCommand(userId, tenantId, request.FileId, request.FileName, request.TotalChunks);
        var result = await _mediator.Send(command, ct);
        return Ok(ApiResponse<UploadSessionDto>.Ok(result));
    }

    [HttpPut("upload/{sessionId:guid}/chunk/{index:int}")]
    [ProducesResponseType(typeof(ApiResponse<ChunkUploadResultDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status409Conflict)]
    [RequestSizeLimit(50 * 1024 * 1024)] // 50 MB per chunk
    public async Task<IActionResult> UploadChunk(
        Guid sessionId, int index, [FromHeader(Name = "X-Chunk-Hash")] string chunkHash, CancellationToken ct)
    {
        var command = new UploadChunkCommand(sessionId, index, chunkHash, Request.Body);
        var result = await _mediator.Send(command, ct);
        return Ok(ApiResponse<ChunkUploadResultDto>.Ok(result));
    }

    [HttpPost("upload/{sessionId:guid}/complete")]
    [ProducesResponseType(typeof(ApiResponse<UploadCompleteDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> CompleteUpload(Guid sessionId, CancellationToken ct)
    {
        var command = new CompleteUploadCommand(sessionId);
        var result = await _mediator.Send(command, ct);
        return Ok(ApiResponse<UploadCompleteDto>.Ok(result));
    }

    [HttpGet("download/{fileId:guid}")]
    [ProducesResponseType(typeof(ApiResponse<DownloadUrlDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> GetDownloadUrl(Guid fileId, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;

        var query = new GetDownloadUrlQuery(tenantId, userId, fileId);
        var result = await _mediator.Send(query, ct);
        return Ok(ApiResponse<DownloadUrlDto>.Ok(result));
    }

    [HttpGet("download/{fileId:guid}/chunk/{hash}")]
    [ProducesResponseType(typeof(ApiResponse<DownloadUrlDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> GetChunkDownloadUrl(Guid fileId, string hash, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;

        var query = new GetChunkDownloadUrlQuery(tenantId, userId, fileId, hash);
        var result = await _mediator.Send(query, ct);
        return Ok(ApiResponse<DownloadUrlDto>.Ok(result));
    }

    [HttpGet("thumbnail/{photoId:guid}")]
    [ProducesResponseType(typeof(ApiResponse<string>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetThumbnailUrl(Guid photoId, [FromQuery] int size = 256, CancellationToken ct = default)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;

        var query = new GetThumbnailUrlQuery(tenantId, userId, photoId, size);
        var result = await _mediator.Send(query, ct);
        return Ok(ApiResponse<string>.Ok(result));
    }

    [HttpDelete("{fileId:guid}")]
    [ProducesResponseType(typeof(ApiResponse<bool>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> DeleteBlob(Guid fileId, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;

        var command = new DeleteBlobCommand(tenantId, userId, fileId);
        var result = await _mediator.Send(command, ct);
        return Ok(ApiResponse<bool>.Ok(result));
    }
}

/// <summary>
/// Request body for upload initialization.
/// </summary>
public sealed record InitUploadRequest(Guid FileId, string FileName, int TotalChunks);
