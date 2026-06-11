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

    public CreateFileVersionCommandHandler(IFileDbContext db, IOptions<VersioningOptions> options)
    {
        _db = db;
        _options = options.Value;
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

        await PruneOldVersionsAsync(request.FileId, cancellationToken);

        await _db.SaveChangesAsync(cancellationToken);

        return version.ToDto();
    }

    /// <summary>
    /// Retention policy: keeps at most MaxVersionsPerFile versions (including
    /// the one being added in this request); the oldest rows are removed.
    /// Blob manifest snapshots are content-addressed and shared, so removing
    /// metadata rows is enough — orphaned snapshots are garbage, not data loss.
    /// </summary>
    private async Task PruneOldVersionsAsync(Guid fileId, CancellationToken cancellationToken)
    {
        if (_options.MaxVersionsPerFile <= 0)
            return;

        // The new version is only in the change tracker — this query hits the
        // database and does not see it. Keeping MaxVersionsPerFile - 1 existing
        // rows therefore yields exactly MaxVersionsPerFile after SaveChanges.
        var excess = await _db.FileVersions
            .Where(v => v.FileId == fileId)
            .OrderByDescending(v => v.VersionNumber)
            .Skip(Math.Max(0, _options.MaxVersionsPerFile - 1))
            .ToListAsync(cancellationToken);

        foreach (var old in excess)
            _db.FileVersions.Remove(old);
    }
}
