using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.RestoreFile;

public sealed class RestoreFileCommandHandler : IRequestHandler<RestoreFileCommand, FileDto>
{
    private readonly IFileDbContext _db;

    public RestoreFileCommandHandler(IFileDbContext db) => _db = db;

    public async Task<FileDto> Handle(RestoreFileCommand request, CancellationToken cancellationToken)
    {
        var node = await _db.FileNodes
            .FirstOrDefaultAsync(f =>
                f.Id == request.FileId
                && f.TenantId == request.TenantId
                && f.UserId == request.UserId
                && f.IsDeleted,
                cancellationToken)
            ?? throw new NotFoundException("FileNode", request.FileId);

        // If the parent folder was also deleted, restore to root.
        if (node.ParentId.HasValue)
        {
            var parentExists = await _db.FileNodes.AnyAsync(f =>
                f.Id == node.ParentId.Value && !f.IsDeleted,
                cancellationToken);

            if (!parentExists)
                node.ParentId = null;
        }

        node.IsDeleted = false;
        node.DeletedAt = null;
        node.UpdatedAt = DateTime.UtcNow;

        // If it's a folder, restore all descendants that were deleted at the same time.
        if (node.IsFolder)
            await RestoreDescendants(node.Id, cancellationToken);

        await _db.SaveChangesAsync(cancellationToken);
        return node.ToDto();
    }

    private async Task RestoreDescendants(Guid parentId, CancellationToken ct)
    {
        var children = await _db.FileNodes
            .Where(f => f.ParentId == parentId && f.IsDeleted)
            .ToListAsync(ct);

        foreach (var child in children)
        {
            child.IsDeleted = false;
            child.DeletedAt = null;
            child.UpdatedAt = DateTime.UtcNow;

            if (child.IsFolder)
                await RestoreDescendants(child.Id, ct);
        }
    }
}
