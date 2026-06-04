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

        // Prevent duplicate names in the same folder.
        var duplicate = await _db.FileNodes.AnyAsync(f =>
            f.TenantId == request.TenantId
            && f.UserId == request.UserId
            && f.ParentId == request.ParentId
            && f.Name == request.Name
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
