using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.Shared.DTOs;
using ZDrive.Shared.Exceptions;

namespace ZDrive.PhotoService.Application.Queries.GetAlbumPhotos;

public sealed class GetAlbumPhotosQueryHandler : IRequestHandler<GetAlbumPhotosQuery, PagedResult<PhotoDto>>
{
    private readonly IPhotoDbContext _db;

    public GetAlbumPhotosQueryHandler(IPhotoDbContext db) => _db = db;

    public async Task<PagedResult<PhotoDto>> Handle(GetAlbumPhotosQuery request, CancellationToken cancellationToken)
    {
        var albumExists = await _db.Albums.AsNoTracking()
            .AnyAsync(a => a.Id == request.AlbumId && a.UserId == request.UserId && a.TenantId == request.TenantId, cancellationToken);
        if (!albumExists)
            throw new NotFoundException("Album", request.AlbumId);

        var query = _db.AlbumPhotos.AsNoTracking()
            .Where(ap => ap.AlbumId == request.AlbumId)
            .OrderBy(ap => ap.SortOrder)
            .Join(
                _db.Photos.AsNoTracking(),
                ap => ap.PhotoId,
                p => p.Id,
                (ap, p) => p);

        var totalCount = await _db.AlbumPhotos
            .CountAsync(ap => ap.AlbumId == request.AlbumId, cancellationToken);

        var photos = await query
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(p => p.ToDto())
            .ToListAsync(cancellationToken);

        return new PagedResult<PhotoDto>
        {
            Items = photos,
            TotalCount = totalCount,
            Page = request.Page,
            PageSize = request.PageSize
        };
    }
}
