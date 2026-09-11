using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Domain.Entities;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.CreateFile;

public sealed class CreateFileCommandHandler : IRequestHandler<CreateFileCommand, FileDto>
{
    private readonly IFileDbContext _db;

    public CreateFileCommandHandler(IFileDbContext db) => _db = db;

    public async Task<FileDto> Handle(CreateFileCommand request, CancellationToken cancellationToken)
    {
        // If a parent is specified, verify it exists and belongs to the same tenant.
        if (request.ParentId.HasValue)
        {
            var parent = await _db.FileNodes
                .FirstOrDefaultAsync(f =>
                    f.Id == request.ParentId.Value
                    && f.TenantId == request.TenantId
                    && f.IsFolder
                    && !f.IsDeleted,
                    cancellationToken)
                ?? throw new NotFoundException("Folder", request.ParentId.Value);
        }

        // Prevent duplicate names in the same folder. Case-insensitive:
        // NTFS and default APFS resolve "Photos" and "photos" to the same
        // directory, so a case-only difference is a real collision, not a
        // cosmetic one (see PR #12 review round 3, B1). Backed by a
        // matching unique index (FileNodeConfiguration) for the race case.
        // f.Name.ToLower() is translated to SQL lower(), which always folds
        // using Postgres's (culture-invariant) default collation.
        // request.Name.ToLower() runs client-side under the CURRENT
        // culture — under Turkish, "FILE".ToLower() is "fıle" (dotless ı)
        // while Postgres's lower() gives "file", so the two sides would
        // silently never match and the insert would proceed to fail on the
        // unique index instead of returning a clean 409. ToLowerInvariant()
        // keeps both sides folding the same way regardless of server
        // locale (PR #12 review round 4).
        var duplicate = await _db.FileNodes.AnyAsync(f =>
            f.TenantId == request.TenantId
            && f.UserId == request.UserId
            && f.ParentId == request.ParentId
            && f.Name.ToLower() == request.Name.ToLowerInvariant()
            && !f.IsDeleted,
            cancellationToken);

        if (duplicate)
            throw new ConflictException($"A file or folder named '{request.Name}' already exists in this location.");

        var node = new FileNode
        {
            Id = Guid.NewGuid(),
            UserId = request.UserId,
            TenantId = request.TenantId,
            ParentId = request.ParentId,
            Name = request.Name,
            IsFolder = request.IsFolder,
            SizeBytes = request.SizeBytes,
            MimeType = request.MimeType,
            BlobPath = request.BlobPath,
            ManifestHash = request.ManifestHash
        };

        _db.FileNodes.Add(node);
        await _db.SaveChangesAsync(cancellationToken);

        return node.ToDto();
    }
}
