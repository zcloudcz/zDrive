using MediatR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Application.Options;
using ZDrive.FileService.Domain.Entities;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.RestoreFileVersion;

public sealed class RestoreFileVersionCommandHandler : IRequestHandler<RestoreFileVersionCommand, FileVersionDto>
{
    private readonly IFileDbContext _db;
    private readonly VersioningOptions _options;
    private readonly IStorageQuota _quota;

    public RestoreFileVersionCommandHandler(IFileDbContext db, IOptions<VersioningOptions> options, IStorageQuota quota)
    {
        _db = db;
        _options = options.Value;
        _quota = quota;
    }

    public async Task<FileVersionDto> Handle(RestoreFileVersionCommand request, CancellationToken cancellationToken)
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

        var source = await _db.FileVersions
            .AsNoTracking()
            .FirstOrDefaultAsync(v => v.Id == request.VersionId && v.FileId == request.FileId, cancellationToken)
            ?? throw new NotFoundException("FileVersion", request.VersionId);

        // Restore records a NEW file_versions row carrying the source's
        // SizeBytes (see CLAUDE.md "Blob versioning" — restore-as-new-version).
        // That row is counted by the usage SUM the same as any other version,
        // so it must clear the same quota check a fresh upload would — net of
        // whatever retention prunes for this same write (see CreateFileVersion-
        // CommandHandler for why: otherwise a user at the limit could never
        // restore a version even when doing so frees more than it adds).
        var toPrune = await SelectVersionsToPruneAsync(request.FileId, cancellationToken);
        var prunedBytes = toPrune.Sum(v => v.SizeBytes);
        var additionalBytes = Math.Max(0, source.SizeBytes - prunedBytes);
        await _quota.EnsureCanStoreAsync(
            request.TenantId, request.UserId, request.ClaimQuotaBytes, additionalBytes, cancellationToken);

        var maxVersion = await _db.FileVersions
            .Where(v => v.FileId == request.FileId)
            .MaxAsync(v => (int?)v.VersionNumber, cancellationToken) ?? 0;

        // Restore-as-new-version: the restored content gets the next version
        // number instead of rewriting history.
        var restored = new FileVersion
        {
            Id = Guid.NewGuid(),
            FileId = request.FileId,
            VersionNumber = maxVersion + 1,
            BlobVersionId = source.BlobVersionId,
            SizeBytes = source.SizeBytes,
            ManifestHash = source.ManifestHash,
            CreatedBy = request.UserId,
            Comment = $"Restored from version {source.VersionNumber}"
        };

        file.SizeBytes = source.SizeBytes;
        file.ManifestHash = source.ManifestHash;
        file.UpdatedAt = DateTime.UtcNow;

        _db.FileVersions.Add(restored);
        _db.FileVersions.RemoveRange(toPrune);
        await _db.SaveChangesAsync(cancellationToken);

        return restored.ToDto();
    }

    /// <summary>
    /// Retention policy: keeps at most MaxVersionsPerFile versions (including
    /// the one being added in this request); the oldest rows are selected for
    /// removal. Single source of truth for "what retention prunes" — used both
    /// to net the quota check against freed bytes and to actually delete.
    /// </summary>
    private async Task<List<FileVersion>> SelectVersionsToPruneAsync(Guid fileId, CancellationToken cancellationToken)
    {
        if (_options.MaxVersionsPerFile <= 0)
            return [];

        // The restored version is still only tracked; reserve one slot for it,
        // just as CreateFileVersion does for a new upload.
        return await _db.FileVersions
            .Where(v => v.FileId == fileId)
            .OrderByDescending(v => v.VersionNumber)
            .Skip(_options.MaxVersionsPerFile - 1)
            .ToListAsync(cancellationToken);
    }
}
