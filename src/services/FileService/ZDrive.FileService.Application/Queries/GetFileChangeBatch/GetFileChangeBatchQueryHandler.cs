using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.FileService.Application.Queries.GetFileChanges;

namespace ZDrive.FileService.Application.Queries.GetFileChangeBatch;

public sealed class GetFileChangeBatchQueryHandler : IRequestHandler<GetFileChangeBatchQuery, FileChangeBatchDto>
{
    private readonly IFileDbContext _db;

    public GetFileChangeBatchQueryHandler(IFileDbContext db) => _db = db;

    public async Task<FileChangeBatchDto> Handle(GetFileChangeBatchQuery request, CancellationToken cancellationToken)
    {
        var page = await FileChangeFeedReader.ReadAsync(
            _db, q => q, request.Cursor, request.Limit, cancellationToken);

        // Read after the feed lock is released. A node may already be newer
        // than the change row that named it; that is fine — a newer change
        // row for it exists further on and re-applies the same state.
        var fileIds = page.Prefix.Select(c => c.FileId).Distinct().ToList();
        var nodes = await _db.FileNodes.AsNoTracking()
            .Where(n => fileIds.Contains(n.Id))
            .ToDictionaryAsync(n => n.Id, cancellationToken);

        var files = page.Prefix
            .GroupBy(c => c.FileId)
            .Select(g =>
            {
                var change = g.First();
                var node = nodes.GetValueOrDefault(g.Key);
                return new ChangedFileDto(
                    g.Key,
                    change.TenantId,
                    change.UserId,
                    node is null
                        ? null
                        : new FileSnapshotDto(
                            node.Name, node.MimeType, node.IsFolder, node.IsDeleted, node.ManifestHash, node.CreatedAt));
            })
            .ToList();

        return new FileChangeBatchDto(files, page.NextCursor, page.HasMore);
    }
}
