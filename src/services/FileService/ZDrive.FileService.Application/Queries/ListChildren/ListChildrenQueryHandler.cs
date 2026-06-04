using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Application.Queries.ListChildren;

public sealed class ListChildrenQueryHandler : IRequestHandler<ListChildrenQuery, PagedResult<FileDto>>
{
    private readonly IFileDbContext _db;

    public ListChildrenQueryHandler(IFileDbContext db) => _db = db;

    public async Task<PagedResult<FileDto>> Handle(ListChildrenQuery request, CancellationToken cancellationToken)
    {
        var query = _db.FileNodes
            .AsNoTracking()
            .Where(f =>
                f.TenantId == request.TenantId
                && f.UserId == request.UserId
                && f.ParentId == request.FolderId
                && !f.IsDeleted)
            .OrderByDescending(f => f.IsFolder)
            .ThenBy(f => f.Name);

        var totalCount = await query.CountAsync(cancellationToken);

        var items = await query
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .ToListAsync(cancellationToken);

        return new PagedResult<FileDto>
        {
            Items = items.Select(f => f.ToDto()).ToList(),
            TotalCount = totalCount,
            Page = request.Page,
            PageSize = request.PageSize
        };
    }
}
