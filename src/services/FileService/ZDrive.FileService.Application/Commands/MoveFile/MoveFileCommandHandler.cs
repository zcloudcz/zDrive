using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.MoveFile;

public sealed class MoveFileCommandHandler : IRequestHandler<MoveFileCommand, FileDto>
{
    private readonly IFileDbContext _db;

    public MoveFileCommandHandler(IFileDbContext db) => _db = db;

    public async Task<FileDto> Handle(MoveFileCommand request, CancellationToken cancellationToken)
    {
        var node = await _db.FileNodes
            .FirstOrDefaultAsync(f =>
                f.Id == request.FileId
                && f.TenantId == request.TenantId
                && f.UserId == request.UserId
                && !f.IsDeleted,
                cancellationToken)
            ?? throw new NotFoundException("FileNode", request.FileId);

        // Validate new parent exists if specified.
        if (request.NewParentId.HasValue)
        {
            var parent = await _db.FileNodes
                .FirstOrDefaultAsync(f =>
                    f.Id == request.NewParentId.Value
                    && f.TenantId == request.TenantId
                    && f.IsFolder
                    && !f.IsDeleted,
                    cancellationToken)
                ?? throw new NotFoundException("Folder", request.NewParentId.Value);

            // Prevent moving a folder into itself or its descendants.
            if (node.IsFolder && await IsDescendant(node.Id, request.NewParentId.Value, cancellationToken))
                throw new ConflictException("Cannot move a folder into one of its own descendants.");
        }

        // Prevent duplicate names in target folder. Case-insensitive —
        // see CreateFileCommandHandler for why.
        var duplicate = await _db.FileNodes.AnyAsync(f =>
            f.TenantId == request.TenantId
            && f.UserId == request.UserId
            && f.ParentId == request.NewParentId
            && f.Name.ToLower() == node.Name.ToLowerInvariant()
            && f.Id != node.Id
            && !f.IsDeleted,
            cancellationToken);

        if (duplicate)
            throw new ConflictException($"A file or folder named '{node.Name}' already exists in the target location.");

        node.ParentId = request.NewParentId;
        node.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(cancellationToken);

        return node.ToDto();
    }

    private async Task<bool> IsDescendant(Guid ancestorId, Guid candidateId, CancellationToken ct)
    {
        var currentId = (Guid?)candidateId;
        while (currentId.HasValue)
        {
            if (currentId.Value == ancestorId)
                return true;

            var parent = await _db.FileNodes
                .Where(f => f.Id == currentId.Value)
                .Select(f => f.ParentId)
                .FirstOrDefaultAsync(ct);
            currentId = parent;
        }
        return false;
    }
}
