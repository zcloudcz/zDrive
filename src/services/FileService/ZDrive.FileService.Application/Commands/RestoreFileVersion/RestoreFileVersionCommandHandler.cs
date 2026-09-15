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

    public RestoreFileVersionCommandHandler(IFileDbContext db, IOptions<VersioningOptions> options)
    {
        _db = db;
        _options = options.Value;
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
        if (_options.MaxVersionsPerFile > 0)
        {
            // The restored version is still only tracked; reserve one slot
            // for it, just as CreateFileVersion does for a new upload.
            var excess = await _db.FileVersions
                .Where(v => v.FileId == request.FileId)
                .OrderByDescending(v => v.VersionNumber)
                .Skip(_options.MaxVersionsPerFile - 1)
                .ToListAsync(cancellationToken);
            _db.FileVersions.RemoveRange(excess);
        }
        await _db.SaveChangesAsync(cancellationToken);

        return restored.ToDto();
    }
}
