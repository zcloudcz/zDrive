using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.FileService.Application.DTOs;
using ZDrive.FileService.Application.Interfaces;
using ZDrive.Shared.DTOs;

namespace ZDrive.FileService.Application.Queries.SearchFiles;

public sealed class SearchFilesQueryHandler : IRequestHandler<SearchFilesQuery, PagedResult<FileDto>>
{
    private readonly IFileDbContext _db;

    public SearchFilesQueryHandler(IFileDbContext db) => _db = db;

    public async Task<PagedResult<FileDto>> Handle(SearchFilesQuery request, CancellationToken cancellationToken)
    {
        var tsQuery = string.Join(" & ",
            request.Query.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(term => term.Replace("'", "''") + ":*"));

        if (string.IsNullOrWhiteSpace(tsQuery))
            return new PagedResult<FileDto>
            {
                Items = [],
                TotalCount = 0,
                Page = request.Page,
                PageSize = request.PageSize
            };

        var query = _db.FileNodes
            .FromSql($@"
                SELECT * FROM files.file_nodes
                WHERE tenant_id = {request.TenantId}
                  AND user_id = {request.UserId}
                  AND is_deleted = false
                  AND name_tsv @@ to_tsquery('simple', {tsQuery})
                ORDER BY ts_rank(name_tsv, to_tsquery('simple', {tsQuery})) DESC")
            .AsNoTracking();

        var allResults = await query.ToListAsync(cancellationToken);
        var totalCount = allResults.Count;

        var items = allResults
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(f => f.ToDto())
            .ToList();

        return new PagedResult<FileDto>
        {
            Items = items,
            TotalCount = totalCount,
            Page = request.Page,
            PageSize = request.PageSize
        };
    }
}
