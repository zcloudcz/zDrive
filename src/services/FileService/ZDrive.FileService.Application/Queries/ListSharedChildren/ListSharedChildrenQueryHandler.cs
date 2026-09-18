using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.Common;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.FileService.Application.Queries.ListSharedChildren;

public sealed class ListSharedChildrenQueryHandler : IRequestHandler<ListSharedChildrenQuery, List<FileDto>>
{
    private readonly IFileDbContext _db;

    public ListSharedChildrenQueryHandler(IFileDbContext db) => _db = db;

    public async Task<List<FileDto>> Handle(ListSharedChildrenQuery request, CancellationToken cancellationToken)
    {
        var share = await PublicShareAccess.LoadShareAsync(_db, request.LinkToken, cancellationToken);

        // Only a folder share can have children at all.
        if (!share.File.IsFolder)
            throw new NotFoundException("FileNode", request.FolderId ?? share.FileId);

        var folderId = request.FolderId ?? share.FileId;
        var folder = await PublicShareAccess.FindWithinShareAsync(_db, share, folderId, cancellationToken);

        // Never Forbidden here: a folderId outside the share must look
        // exactly like an unknown folderId, or the endpoint would confirm
        // the existence of nodes the visitor has no access to.
        if (folder is null || !folder.IsFolder)
            throw new NotFoundException("FileNode", folderId);

        var root = share.File;
        var children = await _db.FileNodes
            .AsNoTracking()
            .Where(f =>
                f.TenantId == root.TenantId
                && f.UserId == root.UserId
                && f.ParentId == folder.Id
                && !f.IsDeleted)
            .OrderByDescending(f => f.IsFolder)
            .ThenBy(f => f.Name)
            .ToListAsync(cancellationToken);

        return children.Select(f => f.ToDto()).ToList();
    }
}
