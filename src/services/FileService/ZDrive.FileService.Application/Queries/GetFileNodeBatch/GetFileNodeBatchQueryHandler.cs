using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;

namespace ZDrive.FileService.Application.Queries.GetFileNodeBatch;

public sealed class GetFileNodeBatchQueryHandler : IRequestHandler<GetFileNodeBatchQuery, FileNodeBatchDto>
{
    private readonly IFileDbContext _db;

    public GetFileNodeBatchQueryHandler(IFileDbContext db) => _db = db;

    public async Task<FileNodeBatchDto> Handle(GetFileNodeBatchQuery request, CancellationToken cancellationToken)
    {
        var query = _db.FileNodes.AsNoTracking().Where(n => !n.IsFolder && !n.IsDeleted);
        if (request.AfterId is { } after)
            query = query.Where(n => n.Id.CompareTo(after) > 0);

        var nodes = await query.OrderBy(n => n.Id).Take(request.Limit).ToListAsync(cancellationToken);

        var files = nodes
            .Select(n => new ChangedFileDto(
                n.Id, n.TenantId, n.UserId,
                new FileSnapshotDto(n.Name, n.MimeType, n.IsFolder, n.IsDeleted, n.ManifestHash, n.CreatedAt)))
            .ToList();

        return new FileNodeBatchDto(files, nodes.Count > 0 ? nodes[^1].Id : request.AfterId, nodes.Count == request.Limit);
    }
}
