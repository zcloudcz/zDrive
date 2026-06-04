using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.Shared.DTOs;

namespace ZDrive.PhotoService.Application.Queries.SearchPhotos;

public sealed class SearchPhotosQueryHandler : IRequestHandler<SearchPhotosQuery, PagedResult<PhotoDto>>
{
    private readonly IPhotoDbContext _db;

    public SearchPhotosQueryHandler(IPhotoDbContext db) => _db = db;

    public async Task<PagedResult<PhotoDto>> Handle(SearchPhotosQuery request, CancellationToken cancellationToken)
    {
        // Find photo IDs that match the tag search, ordered by best confidence
        var matchingPhotoIds = _db.PhotoTags.AsNoTracking()
            .Where(t => EF.Functions.ILike(t.Tag, $"%{request.Query}%"))
            .Join(
                _db.Photos.AsNoTracking()
                    .Where(p => p.UserId == request.UserId && p.TenantId == request.TenantId),
                tag => tag.PhotoId,
                photo => photo.Id,
                (tag, photo) => new { tag.PhotoId, tag.Confidence })
            .GroupBy(x => x.PhotoId)
            .Select(g => new { PhotoId = g.Key, MaxConfidence = g.Max(x => x.Confidence) })
            .OrderByDescending(x => x.MaxConfidence);

        var totalCount = await matchingPhotoIds.CountAsync(cancellationToken);

        var pagedIds = await matchingPhotoIds
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(x => x.PhotoId)
            .ToListAsync(cancellationToken);

        var photos = await _db.Photos.AsNoTracking()
            .Where(p => pagedIds.Contains(p.Id))
            .ToListAsync(cancellationToken);

        // Preserve the ranked order from pagedIds
        var ordered = pagedIds
            .Select(id => photos.First(p => p.Id == id).ToDto())
            .ToList();

        return new PagedResult<PhotoDto>
        {
            Items = ordered,
            TotalCount = totalCount,
            Page = request.Page,
            PageSize = request.PageSize
        };
    }
}
