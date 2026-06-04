using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Commands.DeleteFile;

public sealed class DeleteFileCommandHandler : IRequestHandler<DeleteFileCommand, bool>
{
    private readonly IFileDbContext _db;

    public DeleteFileCommandHandler(IFileDbContext db) => _db = db;

    public async Task<bool> Handle(DeleteFileCommand request, CancellationToken cancellationToken)
    {
        var node = await _db.FileNodes
            .FirstOrDefaultAsync(f =>
                f.Id == request.FileId
                && f.TenantId == request.TenantId
                && f.UserId == request.UserId
                && !f.IsDeleted,
                cancellationToken)
            ?? throw new NotFoundException("FileNode", request.FileId);

        var now = DateTime.UtcNow;
        node.IsDeleted = true;
        node.DeletedAt = now;
        node.UpdatedAt = now;

        // If it's a folder, soft-delete all descendants recursively.
        if (node.IsFolder)
            await SoftDeleteDescendants(node.Id, now, cancellationToken);

        await _db.SaveChangesAsync(cancellationToken);
        return true;
    }

    private async Task SoftDeleteDescendants(Guid parentId, DateTime now, CancellationToken ct)
    {
        var children = await _db.FileNodes
            .Where(f => f.ParentId == parentId && !f.IsDeleted)
            .ToListAsync(ct);

        foreach (var child in children)
        {
            child.IsDeleted = true;
            child.DeletedAt = now;
            child.UpdatedAt = now;

            if (child.IsFolder)
                await SoftDeleteDescendants(child.Id, now, ct);
        }
    }
}
