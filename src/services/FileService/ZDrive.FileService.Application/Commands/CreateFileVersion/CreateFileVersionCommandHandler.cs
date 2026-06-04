using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Domain.Entities;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.CreateFileVersion;

public sealed class CreateFileVersionCommandHandler : IRequestHandler<CreateFileVersionCommand, FileVersionDto>
{
    private readonly IFileDbContext _db;

    public CreateFileVersionCommandHandler(IFileDbContext db) => _db = db;

    public async Task<FileVersionDto> Handle(CreateFileVersionCommand request, CancellationToken cancellationToken)
    {
        var file = await _db.FileNodes
            .FirstOrDefaultAsync(f => f.Id == request.FileId && !f.IsDeleted && !f.IsFolder, cancellationToken)
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
            CreatedBy = request.CreatedBy,
            Comment = request.Comment
        };

        // Update the file's size and manifest hash to the latest version.
        file.SizeBytes = request.SizeBytes;
        file.ManifestHash = request.ManifestHash;
        file.UpdatedAt = DateTime.UtcNow;

        _db.FileVersions.Add(version);
        await _db.SaveChangesAsync(cancellationToken);

        return version.ToDto();
    }
}
