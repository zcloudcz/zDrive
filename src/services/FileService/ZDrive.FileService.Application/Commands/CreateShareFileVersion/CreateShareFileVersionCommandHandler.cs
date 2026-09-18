using MediatR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using ZDrive.FileService.Application.Commands.CreateFileVersion;
using ZDrive.FileService.Application.Common;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Auth;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.CreateShareFileVersion;

/// <summary>
/// POST /shares/link/{token}/files/{fileId}/versions — records the version
/// StorageService already wrote, using size + manifest hash FROM THE RECEIPT
/// (never the caller's own claim). Idempotent: a replayed receipt (retried
/// request, or a client that calls this twice) must not create a second
/// identical version, so it short-circuits when the file's current version
/// already carries that manifest hash.
/// </summary>
public sealed class CreateShareFileVersionCommandHandler : IRequestHandler<CreateShareFileVersionCommand, FileDto>
{
    private readonly IFileDbContext _db;
    private readonly IMediator _mediator;
    private readonly ShareDownloadGrantOptions _options;

    public CreateShareFileVersionCommandHandler(
        IFileDbContext db, IMediator mediator, IOptions<ShareDownloadGrantOptions> options)
    {
        _db = db;
        _mediator = mediator;
        _options = options.Value;
    }

    public async Task<FileDto> Handle(CreateShareFileVersionCommand request, CancellationToken cancellationToken)
    {
        if (!_options.TryGetKey(out var key)
            || !ShareUploadReceipt.TryValidate(request.Receipt, key, DateTimeOffset.UtcNow, out var receipt)
            // The receipt is bound to one fileId — a receipt for file X must
            // not record a version on file Y, even inside the same share.
            || receipt.FileId != request.FileId)
        {
            throw new NotFoundException("ShareUploadReceipt", "invalid");
        }

        var share = await PublicShareAccess.LoadShareAsync(_db, request.LinkToken, cancellationToken);
        PublicShareAccess.RequireWrite(share);

        var file = await PublicShareAccess.FindWithinShareAsync(_db, share, request.FileId, cancellationToken);
        if (file is null || file.IsFolder)
            throw new NotFoundException("FileNode", request.FileId);

        // Idempotent replay: the current version already IS these bytes.
        if (file.ManifestHash == receipt.ManifestHash)
            return file.ToDto().ToPublicDto();

        await _mediator.Send(new CreateFileVersionCommand(
            file.TenantId, file.UserId, file.Id, receipt.ManifestHash, receipt.SizeBytes, receipt.ManifestHash, Comment: null),
            cancellationToken);

        var updated = await _db.FileNodes.AsNoTracking().FirstAsync(f => f.Id == file.Id, cancellationToken);
        return updated.ToDto().ToPublicDto();
    }
}
