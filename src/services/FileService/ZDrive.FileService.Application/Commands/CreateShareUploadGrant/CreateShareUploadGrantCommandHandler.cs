using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using ZDrive.FileService.Application.Commands.CreateFile;
using ZDrive.FileService.Application.Common;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Domain.Entities;
using ZDrive.Shared.Auth;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.CreateShareUploadGrant;

/// <summary>
/// POST /shares/link/{token}/upload-grant — mints a ShareUploadGrant that
/// StorageService trusts to bind an anonymous shared upload session to
/// (tenant, owner, fileId), and pre-creates the destination FileNode so the
/// grant has an id to address (mirrors CreateFile's own "empty node left
/// behind if the upload never completes" behaviour for the authenticated flow).
/// </summary>
public sealed class CreateShareUploadGrantCommandHandler
    : IRequestHandler<CreateShareUploadGrantCommand, ShareUploadGrantResultDto>
{
    // Same reasoning as CreateShareDownloadGrantCommandHandler's GrantTtl:
    // StorageService can't see FileService state, so the grant's own TTL is
    // the only revocation window a share change gets once a grant is issued.
    private static readonly TimeSpan GrantTtl = TimeSpan.FromHours(1);

    private readonly IFileDbContext _db;
    private readonly IMediator _mediator;
    private readonly IStorageQuota _quota;
    private readonly ShareDownloadGrantOptions _options;

    public CreateShareUploadGrantCommandHandler(
        IFileDbContext db, IMediator mediator, IStorageQuota quota, IOptions<ShareDownloadGrantOptions> options)
    {
        _db = db;
        _mediator = mediator;
        _quota = quota;
        _options = options.Value;
    }

    public async Task<ShareUploadGrantResultDto> Handle(
        CreateShareUploadGrantCommand request, CancellationToken cancellationToken)
    {
        if (!_options.TryGetKey(out var key))
            throw new NotFoundException("Share", "invalid");

        var share = await PublicShareAccess.LoadShareAsync(_db, request.LinkToken, cancellationToken);
        PublicShareAccess.RequireWrite(share);

        var owner = share.File;
        FileNode targetFile;

        if (!owner.IsFolder)
        {
            // Shared root that is itself a single file: the grant always
            // targets that file (a new version of it), never a sibling.
            if (!request.Overwrite)
                throw new ConflictException("This share points at a single file; overwrite must be true.");

            await _quota.EnsureCanStoreAsync(owner.TenantId, owner.UserId, claimLimit: null, request.SizeBytes, cancellationToken);
            targetFile = owner;
        }
        else
        {
            if (string.IsNullOrWhiteSpace(request.FileName))
                throw new ValidationException("fileName is required when the share root is a folder.");

            var parentId = request.ParentId ?? share.FileId;
            var parent = await PublicShareAccess.FindWithinShareAsync(_db, share, parentId, cancellationToken);
            if (parent is null || !parent.IsFolder)
                throw new NotFoundException("Folder", parentId);

            var existing = await _db.FileNodes.FirstOrDefaultAsync(f =>
                f.TenantId == owner.TenantId
                && f.UserId == owner.UserId
                && f.ParentId == parent.Id
                && f.Name.ToLower() == request.FileName.ToLowerInvariant()
                && !f.IsDeleted,
                cancellationToken);

            if (existing is not null && existing.IsFolder)
                throw new ConflictException($"A folder named '{request.FileName}' already exists in this location.");

            if (existing is not null)
            {
                if (!request.Overwrite)
                    throw new ConflictException($"A file named '{request.FileName}' already exists in this location.");

                await _quota.EnsureCanStoreAsync(owner.TenantId, owner.UserId, claimLimit: null, request.SizeBytes, cancellationToken);
                targetFile = existing;
            }
            else
            {
                // CreateFileCommandHandler does its own quota pre-check.
                var createCommand = new CreateFileCommand(
                    owner.UserId, owner.TenantId, parent.Id, request.FileName, IsFolder: false,
                    SizeBytes: request.SizeBytes, MimeType: null, BlobPath: null, ManifestHash: null);
                var created = await _mediator.Send(createCommand, cancellationToken);
                targetFile = await _db.FileNodes.FirstAsync(f => f.Id == created.Id, cancellationToken);
            }
        }

        var uncappedExpiry = DateTimeOffset.UtcNow.Add(GrantTtl);
        var shareExpiresAt = share.ExpiresAt.HasValue
            ? new DateTimeOffset(DateTime.SpecifyKind(share.ExpiresAt.Value, DateTimeKind.Utc))
            : (DateTimeOffset?)null;
        var expiresAt = shareExpiresAt.HasValue && shareExpiresAt.Value < uncappedExpiry
            ? shareExpiresAt.Value
            : uncappedExpiry;

        var payload = new ShareUploadGrant.Payload(
            targetFile.TenantId, targetFile.UserId, targetFile.Id, request.SizeBytes, expiresAt);
        var grant = ShareUploadGrant.Create(payload, key);

        return new ShareUploadGrantResultDto(grant, expiresAt, targetFile.Id, targetFile.Name, request.SizeBytes);
    }
}
