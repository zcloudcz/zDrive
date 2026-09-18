using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using ZDrive.Shared.Auth;
using ZDrive.Shared.DTOs;
using ZDrive.Shared.Exceptions;
using ZDrive.StorageService.Application.Common;
using ZDrive.StorageService.Application.DTOs;
using ZDrive.StorageService.Application.Queries.DownloadChunk;
using ZDrive.StorageService.Application.Queries.GetManifest;

namespace ZDrive.StorageService.Api.Controllers;

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
            throw new NotFoundException("ShareDownloadGrant", grant ?? string.Empty);
        }

        return payload;
    }
}
