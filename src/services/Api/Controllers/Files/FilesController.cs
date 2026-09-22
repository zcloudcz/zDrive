using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZDrive.FileService.Application.Commands.CreateFile;
using ZDrive.FileService.Application.Commands.DeleteFile;
using ZDrive.FileService.Application.Commands.EmptyTrash;
using ZDrive.FileService.Application.Commands.MoveFile;
using ZDrive.FileService.Application.Commands.RenameFile;
using ZDrive.FileService.Application.Commands.CreateFileVersion;
using ZDrive.FileService.Application.Commands.RestoreFile;
using ZDrive.FileService.Application.Commands.RestoreFileVersion;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Application.Queries.GetFile;
using ZDrive.FileService.Application.Queries.GetFileChanges;
using ZDrive.FileService.Application.Queries.GetFileVersions;
using ZDrive.FileService.Application.Queries.GetStorageUsage;
using ZDrive.FileService.Application.Queries.ListChildren;
using ZDrive.FileService.Application.Queries.ListTrash;
using ZDrive.FileService.Application.Queries.SearchFiles;
using ZDrive.Shared.Auth;
using ZDrive.Shared.DTOs;

namespace ZDrive.Api.Controllers.Files;

[ApiController]
[Route("api/v1/files")]
[Authorize]
public sealed class FilesController : ControllerBase
{
    private readonly IMediator _mediator;
    private readonly IChangeOrigin _changeOrigin;

    public FilesController(IMediator mediator, IChangeOrigin changeOrigin)
    {
        _mediator = mediator;
        _changeOrigin = changeOrigin;
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(ApiResponse<FileDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetFile(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(new GetFileQuery(userId, tenantId, id), ct);
        return Ok(ApiResponse<FileDto>.Ok(result));
    }

    [HttpGet("{id:guid}/children")]
    [ProducesResponseType(typeof(ApiResponse<PagedResult<FileDto>>), StatusCodes.Status200OK)]
    public async Task<IActionResult> ListChildren(
        Guid id,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(new ListChildrenQuery(userId, tenantId, id, page, pageSize), ct);
        return Ok(ApiResponse<PagedResult<FileDto>>.Ok(result));
    }

    /// <summary>
    /// Lists items at the root (no parent). Separate route because the
    /// "{id:guid}/children" route cannot express a null parent.
    /// </summary>
    [HttpGet("root/children")]
    [ProducesResponseType(typeof(ApiResponse<PagedResult<FileDto>>), StatusCodes.Status200OK)]
    public async Task<IActionResult> ListRootChildren(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(new ListChildrenQuery(userId, tenantId, null, page, pageSize), ct);
        return Ok(ApiResponse<PagedResult<FileDto>>.Ok(result));
    }

    [HttpPost]
    [ProducesResponseType(typeof(ApiResponse<FileDto>), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status409Conflict)]
    public async Task<IActionResult> CreateFile([FromBody] CreateFileRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var command = new CreateFileCommand(
            userId, tenantId, request.ParentId, request.Name, request.IsFolder,
            request.SizeBytes, request.MimeType, request.BlobPath, request.ManifestHash,
            User.GetQuotaBytes());
        var result = await _mediator.Send(command, ct);
        return CreatedAtAction(nameof(GetFile), new { id = result.Id }, ApiResponse<FileDto>.Ok(result));
    }

    [HttpPut("{id:guid}/rename")]
    [ProducesResponseType(typeof(ApiResponse<FileDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> RenameFile(Guid id, [FromBody] RenameFileRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(new RenameFileCommand(userId, tenantId, id, request.NewName), ct);
        return Ok(ApiResponse<FileDto>.Ok(result));
    }

    [HttpPut("{id:guid}/move")]
    [ProducesResponseType(typeof(ApiResponse<FileDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> MoveFile(Guid id, [FromBody] MoveFileRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(new MoveFileCommand(userId, tenantId, id, request.NewParentId), ct);
        return Ok(ApiResponse<FileDto>.Ok(result));
    }

    [HttpDelete("{id:guid}")]
    [ProducesResponseType(typeof(ApiResponse<bool>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeleteFile(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(new DeleteFileCommand(userId, tenantId, id), ct);
        return Ok(ApiResponse<bool>.Ok(result));
    }

    [HttpPost("{id:guid}/restore")]
    [ProducesResponseType(typeof(ApiResponse<FileDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> RestoreFile(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(new RestoreFileCommand(userId, tenantId, id), ct);
        return Ok(ApiResponse<FileDto>.Ok(result));
    }

    [HttpGet("trash")]
    [ProducesResponseType(typeof(ApiResponse<PagedResult<FileDto>>), StatusCodes.Status200OK)]
    public async Task<IActionResult> ListTrash(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(new ListTrashQuery(userId, tenantId, page, pageSize), ct);
        return Ok(ApiResponse<PagedResult<FileDto>>.Ok(result));
    }

    [HttpDelete("trash")]
    [ProducesResponseType(typeof(ApiResponse<int>), StatusCodes.Status200OK)]
    public async Task<IActionResult> EmptyTrash(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(new EmptyTrashCommand(userId, tenantId), ct);
        return Ok(ApiResponse<int>.Ok(result));
    }

    [HttpGet("search")]
    [ProducesResponseType(typeof(ApiResponse<PagedResult<FileDto>>), StatusCodes.Status200OK)]
    public async Task<IActionResult> SearchFiles(
        [FromQuery] string q = "",
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(new SearchFilesQuery(userId, tenantId, q, page, pageSize), ct);
        return Ok(ApiResponse<PagedResult<FileDto>>.Ok(result));
    }

    /// <summary>
    /// Records a new version after a completed upload. The client passes the
    /// manifest hash returned by StorageService's upload-complete response.
    /// </summary>
    [HttpPost("{id:guid}/versions")]
    [ProducesResponseType(typeof(ApiResponse<FileVersionDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> CreateFileVersion(
        Guid id, [FromBody] CreateFileVersionRequest request, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;
        var result = await _mediator.Send(new CreateFileVersionCommand(
            tenantId, userId, id, request.BlobVersionId, request.SizeBytes, request.ManifestHash, request.Comment,
            User.GetQuotaBytes()), ct);
        return Ok(ApiResponse<FileVersionDto>.Ok(result));
    }

    /// <summary>
    /// Restores an older version (metadata side). The client must follow up
    /// with StorageService restore-manifest to flip the blob-side manifest.
    /// </summary>
    [HttpPost("{id:guid}/versions/{versionId:guid}/restore")]
    [ProducesResponseType(typeof(ApiResponse<FileVersionDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ApiResponse<object>), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> RestoreFileVersion(Guid id, Guid versionId, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? userId;
        var result = await _mediator.Send(
            new RestoreFileVersionCommand(tenantId, userId, id, versionId, User.GetQuotaBytes()), ct);
        return Ok(ApiResponse<FileVersionDto>.Ok(result));
    }

    [HttpGet("{id:guid}/versions")]
    [ProducesResponseType(typeof(ApiResponse<List<FileVersionDto>>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetFileVersions(Guid id, CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(new GetFileVersionsQuery(userId, tenantId, id), ct);
        return Ok(ApiResponse<List<FileVersionDto>>.Ok(result));
    }

    /// <summary>
    /// Current per-user storage usage against the quota (JWT quota_bytes
    /// claim, else the configured default).
    /// </summary>
    [HttpGet("usage")]
    [ProducesResponseType(typeof(ApiResponse<StorageUsage>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetStorageUsage(CancellationToken ct)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(new GetStorageUsageQuery(tenantId, userId, User.GetQuotaBytes()), ct);
        return Ok(ApiResponse<StorageUsage>.Ok(result));
    }

    /// <summary>
    /// Cursor-paged feed of file changes for sync clients. Excludes changes
    /// that originated from the caller's own device (X-Device-Id) so a
    /// device does not download back the writes it just made.
    /// </summary>
    [HttpGet("changes")]
    [ProducesResponseType(typeof(ApiResponse<FileChangesPageDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetFileChanges(
        [FromQuery] long cursor = 0,
        [FromQuery] int limit = 500,
        CancellationToken ct = default)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId() ?? throw new InvalidOperationException("Tenant ID claim is missing.");
        var result = await _mediator.Send(
            new GetFileChangesQuery(userId, tenantId, cursor, limit, _changeOrigin.DeviceId), ct);
        return Ok(ApiResponse<FileChangesPageDto>.Ok(result));
    }
}

public sealed record CreateFileRequest(
    string Name,
    Guid? ParentId,
    bool IsFolder,
    long? SizeBytes = null,
    string? MimeType = null,
    string? BlobPath = null,
    string? ManifestHash = null);

public sealed record RenameFileRequest(string NewName);

public sealed record MoveFileRequest(Guid? NewParentId);

public sealed record CreateFileVersionRequest(
    string BlobVersionId,
    long SizeBytes,
    string? ManifestHash,
    string? Comment);
