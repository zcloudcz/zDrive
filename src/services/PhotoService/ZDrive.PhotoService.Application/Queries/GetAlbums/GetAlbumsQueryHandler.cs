using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Application.Interfaces;

namespace ZDrive.PhotoService.Application.Queries.GetAlbums;

public sealed class GetAlbumsQueryHandler : IRequestHandler<GetAlbumsQuery, List<AlbumDto>>
{
    private readonly IPhotoDbContext _db;

    public GetAlbumsQueryHandler(IPhotoDbContext db) => _db = db;

    public async Task<List<AlbumDto>> Handle(GetAlbumsQuery request, CancellationToken cancellationToken)
    {
        var albums = await _db.Albums.AsNoTracking()
            .Where(a => a.UserId == request.UserId && a.TenantId == request.TenantId)
            .OrderByDescending(a => a.UpdatedAt)
            .Select(a => new
            {
                Album = a,
                PhotoCount = _db.AlbumPhotos.Count(ap => ap.AlbumId == a.Id)
            })
            .ToListAsync(cancellationToken);

        return albums.Select(x => x.Album.ToDto(x.PhotoCount)).ToList();
    }
}
