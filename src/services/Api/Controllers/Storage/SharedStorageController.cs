using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using ZDrive.Shared.Auth;
using ZDrive.Shared.DTOs;
using ZDrive.Shared.Exceptions;
using ZDrive.Shared.Http;
using ZDrive.StorageService.Application.Commands.AbortUpload;
using ZDrive.StorageService.Application.Commands.CompleteUpload;
using ZDrive.StorageService.Application.Commands.InitUpload;
using ZDrive.StorageService.Application.Commands.UploadChunk;
using ZDrive.StorageService.Application.Common;
using ZDrive.StorageService.Application.DTOs;
using ZDrive.StorageService.Application.Queries.DownloadChunk;
using ZDrive.StorageService.Application.Queries.GetManifest;

namespace ZDrive.Api.Controllers.Storage;

/// <summary>
/// Anonymous download endpoints for public share links. Authenticated by a
/// ShareDownloadGrant (see ZDrive.Shared) carried in the X-Share-Grant
/// header rather than a JWT — a link visitor has no tenant/user of their
/// own, and the grant addresses the OWNER's blob path instead.
///
/// The grant travels as a header, never a query string: query strings end
/// up in server access logs and browser history, and this token is a bearer
/// credential for someone else's files.
///
/// A missing/invalid/expired grant and a chunk hash outside the granted
/// manifest both answer plain 404 — there is nothing to gain by telling an
/// attacker which check failed.
/// </summary>
[ApiController]
[Route("api/v1/storage/shared")]
[AllowAnonymous]
public sealed class SharedStorageController : ControllerBase
{
    private readonly IMediator _mediator;
    private readonly ShareDownloadGrantOptions _options;

    public SharedStorageController(IMediator mediator, IOptions<ShareDownloadGrantOptions> options)
    {
        _mediator = mediator;
        _options = options.Value;
    }

    [HttpGet("manifest")]
    [ProducesResponseType(typeof(ApiResponse<ManifestDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetSharedManifest(
        [FromHeader(Name = "X-Share-Grant")] string? grant, CancellationToken ct)
    {
        // Set before anything below can throw, so it lands on the 404 too — see
        // ShareResponseHeaderExtensions for why this endpoint must never be cached.
        Response.SetPublicShareCacheHeaders();

        var payload = ValidateGrantOrThrow(grant);
        var query = new GetManifestQuery(payload.TenantId, payload.OwnerUserId, payload.FileId, payload.ManifestHash);
        var result = await _mediator.Send(query, ct);
        return Ok(ApiResponse<ManifestDto>.Ok(result));
    }

    [HttpGet("chunk/{hash}/bytes")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DownloadSharedChunk(
        string hash, [FromHeader(Name = "X-Share-Grant")] string? grant, CancellationToken ct)
    {
        Response.SetPublicShareCacheHeaders();

        var payload = ValidateGrantOrThrow(grant);

        // ponytail: re-reads the manifest per chunk; cache per grant if public download throughput matters
        var manifest = await _mediator.Send(
            new GetManifestQuery(payload.TenantId, payload.OwnerUserId, payload.FileId, payload.ManifestHash), ct);
        if (!SharedChunkAccess.IsChunkInManifest(manifest, hash))
            throw new NotFoundException("Chunk", hash);

        var stream = await _mediator.Send(
            new DownloadChunkQuery(payload.TenantId, payload.OwnerUserId, payload.FileId, hash), ct);
        return File(stream, "application/octet-stream");
    }

    private ShareDownloadGrant.Payload ValidateGrantOrThrow(string? grant)
    {
        if (!_options.TryGetKey(out var key)
            || !ShareDownloadGrant.TryValidate(grant, key, DateTimeOffset.UtcNow, out var payload))
        {
            // Never the grant itself here: NotFoundException's message embeds
            // its "key" verbatim, and that would put a bearer credential for
            // someone else's files into the response body and the Warning log.
            throw new NotFoundException("ShareDownloadGrant", "invalid");
        }

        return payload;
    }

    // --- Shared (link-driven) upload: X-Share-Grant carries a ShareUploadGrant ---

    [HttpPost("upload/init")]
    [ProducesResponseType(typeof(ApiResponse<UploadSessionDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status413PayloadTooLarge)]
    public async Task<IActionResult> InitSharedUpload(
        [FromHeader(Name = "X-Share-Grant")] string? grant,
        [FromBody] InitSharedUploadRequest request, CancellationToken ct)
    {
        Response.SetPublicShareCacheHeaders();

        var payload = ValidateUploadGrantOrThrow(grant);
        var command = new InitUploadCommand(
            payload.OwnerUserId, payload.TenantId, payload.FileId, request.FileName, request.TotalChunks,
            payload.MaxBytes, IsShared: true, payload.QuotaRemainingBytes);
        var result = await _mediator.Send(command, ct);
        return Ok(ApiResponse<UploadSessionDto>.Ok(result));
    }

    [HttpPut("upload/{sessionId:guid}/chunk/{index:int}")]
    [ProducesResponseType(typeof(ApiResponse<ChunkUploadResultDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status413PayloadTooLarge)]
    [RequestSizeLimit(50 * 1024 * 1024)] // same cap as the authenticated chunk route — never stricter
    public async Task<IActionResult> UploadSharedChunk(
        Guid sessionId, int index,
        [FromHeader(Name = "X-Share-Grant")] string? grant,
        [FromHeader(Name = "X-Chunk-Hash")] string chunkHash, CancellationToken ct)
    {
        Response.SetPublicShareCacheHeaders();

        var payload = ValidateUploadGrantOrThrow(grant);
        var command = new UploadChunkCommand(
            sessionId, index, chunkHash, Request.Body,
            payload.TenantId, payload.OwnerUserId, IsShared: true, payload.FileId);
        var result = await _mediator.Send(command, ct);
        return Ok(ApiResponse<ChunkUploadResultDto>.Ok(result));
    }

    [HttpPost("upload/{sessionId:guid}/complete")]
    [ProducesResponseType(typeof(ApiResponse<SharedUploadCompleteDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> CompleteSharedUpload(
        Guid sessionId, [FromHeader(Name = "X-Share-Grant")] string? grant, CancellationToken ct)
    {
        Response.SetPublicShareCacheHeaders();

        var payload = ValidateUploadGrantOrThrow(grant);
        var command = new CompleteUploadCommand(sessionId, payload.TenantId, payload.OwnerUserId, IsShared: true, payload.FileId);
        var result = await _mediator.Send(command, ct);

        // The receipt is StorageService's proof to FileService that these
        // exact bytes were written for this fileId — short TTL (15 min) since
        // it is only meant to bridge "upload just finished" to "record the
        // version", not to outlive the upload flow.
        if (!_options.TryGetKey(out var key))
            throw new NotFoundException("ShareUploadGrant", "invalid");

        var receiptPayload = new ShareUploadReceipt.Payload(
            payload.FileId, result.ManifestHash, result.TotalSize, DateTimeOffset.UtcNow.AddMinutes(15));
        var receipt = ShareUploadReceipt.Create(receiptPayload, key);

        return Ok(ApiResponse<SharedUploadCompleteDto>.Ok(
            new SharedUploadCompleteDto(result.ManifestHash, result.TotalSize, receipt)));
    }

    [HttpDelete("upload/{sessionId:guid}")]
    [ProducesResponseType(typeof(ApiResponse<bool>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> AbortSharedUpload(
        Guid sessionId, [FromHeader(Name = "X-Share-Grant")] string? grant, CancellationToken ct)
    {
        Response.SetPublicShareCacheHeaders();

        var payload = ValidateUploadGrantOrThrow(grant);
        var result = await _mediator.Send(
            new AbortUploadCommand(sessionId, payload.OwnerUserId, payload.TenantId, IsShared: true, payload.FileId), ct);
        return Ok(ApiResponse<bool>.Ok(result));
    }

    private ShareUploadGrant.Payload ValidateUploadGrantOrThrow(string? grant)
    {
        if (!_options.TryGetKey(out var key)
            || !ShareUploadGrant.TryValidate(grant, key, DateTimeOffset.UtcNow, out var payload))
        {
            throw new NotFoundException("ShareUploadGrant", "invalid");
        }

        return payload;
    }
}

public sealed record InitSharedUploadRequest(string FileName, int TotalChunks);

public sealed record SharedUploadCompleteDto(string ManifestHash, long TotalSize, string Receipt);
