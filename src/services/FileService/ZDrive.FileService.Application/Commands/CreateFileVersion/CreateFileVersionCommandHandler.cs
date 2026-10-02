using MediatR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Application.Options;
using ZDrive.FileService.Domain.Entities;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.CreateFileVersion;

public sealed class CreateFileVersionCommandHandler : IRequestHandler<CreateFileVersionCommand, FileVersionDto>
{
    private readonly IFileDbContext _db;
    private readonly VersioningOptions _options;
    private readonly IStorageQuota _quota;
    private readonly TimeProvider _time;

    public CreateFileVersionCommandHandler(
        IFileDbContext db, IOptions<VersioningOptions> options, IStorageQuota quota, TimeProvider? time = null)
    {
        _db = db;
        _options = options.Value;
        _quota = quota;
        _time = time ?? TimeProvider.System;
    }

    public async Task<FileVersionDto> Handle(CreateFileVersionCommand request, CancellationToken cancellationToken)
    {
        var file = await _db.FileNodes
            .FirstOrDefaultAsync(f =>
                f.Id == request.FileId
                && f.TenantId == request.TenantId
                && f.UserId == request.UserId
                && !f.IsDeleted
                && !f.IsFolder,
                cancellationToken)
            ?? throw new NotFoundException("FileNode", request.FileId);

        // Determine what retention will prune for this write BEFORE checking
        // quota: a write that itself frees old versions must be judged net of
        // those freed bytes — otherwise a user sitting at the limit could
        // never replace even a tiny file whose retention-pruned predecessor
        // was huge, and nothing but manual deletion would unstick them.
        var toPrune = await SelectVersionsToPruneAsync(request.FileId, cancellationToken);
        var prunedBytes = toPrune.Sum(v => v.SizeBytes);
        var additionalBytes = Math.Max(0, request.SizeBytes - prunedBytes);

        // Single enforcement point for the quota check — both the authenticated
        // and the link-driven upload flow (package A) go through this handler.
        await _quota.EnsureCanStoreAsync(
            request.TenantId, request.UserId, request.ClaimQuotaBytes, additionalBytes, cancellationToken);

        var maxVersion = await _db.FileVersions
            .Where(v => v.FileId == request.FileId)
            .MaxAsync(v => (int?)v.VersionNumber, cancellationToken) ?? 0;

        var version = new FileVersion
        {
            Id = Guid.NewGuid(),
            FileId = request.FileId,
            VersionNumber = maxVersion + 1,
            BlobVersionId = request.BlobVersionId,
            SizeBytes = request.SizeBytes,
            ManifestHash = request.ManifestHash,
            CreatedBy = request.UserId,
            Comment = request.Comment
        };

        // Update the file's size and manifest hash to the latest version.
        file.SizeBytes = request.SizeBytes;
        file.ManifestHash = request.ManifestHash;
        file.UpdatedAt = DateTime.UtcNow;

        _db.FileVersions.Add(version);

        // Blob manifest snapshots are content-addressed and shared, so removing
        // metadata rows is enough — orphaned snapshots are garbage, not data loss.
        foreach (var old in toPrune)
            _db.FileVersions.Remove(old);

        await _db.SaveChangesAsync(cancellationToken);

        return version.ToDto();
    }

    /// <summary>
    /// Retention policy (see <see cref="VersionRetention"/>): keeps at least the
    /// newest MaxVersionsPerFile versions (including the one being added in
    /// this request) and any version younger than MinRetentionDays. Single
    /// source of truth for "what retention prunes" — used both to net the quota
    /// check against freed bytes and to actually delete.
    /// </summary>
    private async Task<List<FileVersion>> SelectVersionsToPruneAsync(Guid fileId, CancellationToken cancellationToken)
    {
        if (_options.MaxVersionsPerFile <= 0)
            return [];

        // The new version is only in the change tracker — this query hits the
        // database and does not see it. Keeping MaxVersionsPerFile - 1 existing
        // rows therefore yields MaxVersionsPerFile after SaveChanges (more when
        // MinRetentionDays keeps younger versions).
        return await VersionRetention
            .SelectPrunable(_db.FileVersions.Where(v => v.FileId == fileId), _options, _time.GetUtcNow().UtcDateTime)
            .ToListAsync(cancellationToken);
    }
}
