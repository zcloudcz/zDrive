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
                // A NEW node is created before any byte moves, so an abusive
                // caller who never uploads still leaves a permanent node
                // behind (same behaviour as the authenticated CreateFile flow
                // — accepted there because a real client account can only do
                // it to itself). A public link isn't rate-limited by an
                // account, so cap how many such versionless nodes one owner
                // can accumulate from link traffic in a day; reusing an
                // existing node (the overwrite branches above) doesn't count,
                // since it creates nothing.
                // ponytail: fixed 100/24h ceiling, not per-share or configurable;
                // revisit once blob GC exists and this stops being the only backstop.
                // ponytail: this counts ALL of the owner's versionless nodes
                // from the last 24h, including ones the owner's own
                // authenticated client created (it keeps up to ~3 uploads in
                // flight, and a failed one can linger versionless) — not just
                // link-created ones, so a very active legitimate owner could
                // in theory eat into this budget themselves. Upgrade path: a
                // column tagging which nodes were created via a share link,
                // and count only those.
                var pendingCutoff = DateTime.UtcNow.AddHours(-24);
                var pendingCount = await _db.FileNodes.CountAsync(f =>
                    f.TenantId == owner.TenantId && f.UserId == owner.UserId && !f.IsFolder && !f.IsDeleted
                    && f.CreatedAt >= pendingCutoff
                    && !_db.FileVersions.Any(v => v.FileId == f.Id),
                    cancellationToken);
                if (pendingCount >= MaxPendingUploadsPerDay)
                    throw new TooManyRequestsException("Too many pending uploads through share links in the last 24 hours.");

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

        var usage = await _quota.GetUsageAsync(owner.TenantId, owner.UserId, claimLimit: null, cancellationToken);
        var quotaRemaining = Math.Max(0, usage.LimitBytes - usage.UsedBytes);

        var payload = new ShareUploadGrant.Payload(
            targetFile.TenantId, targetFile.UserId, targetFile.Id, request.SizeBytes, expiresAt, quotaRemaining);
        var grant = ShareUploadGrant.Create(payload, key);

        return new ShareUploadGrantResultDto(grant, expiresAt, targetFile.Id, targetFile.Name, request.SizeBytes);
    }

    private const int MaxPendingUploadsPerDay = 100;
}
