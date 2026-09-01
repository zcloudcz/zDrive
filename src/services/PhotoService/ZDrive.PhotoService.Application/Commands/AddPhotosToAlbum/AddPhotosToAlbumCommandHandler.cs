using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.PhotoService.Domain.Entities;
using ZDrive.Shared.Exceptions;

namespace ZDrive.PhotoService.Application.Commands.AddPhotosToAlbum;

public sealed class AddPhotosToAlbumCommandHandler : IRequestHandler<AddPhotosToAlbumCommand, int>
{
    private readonly IPhotoDbContext _db;

    public AddPhotosToAlbumCommandHandler(IPhotoDbContext db) => _db = db;

    public async Task<int> Handle(AddPhotosToAlbumCommand request, CancellationToken cancellationToken)
    {
        var album = await _db.Albums
            .FirstOrDefaultAsync(a => a.Id == request.AlbumId && a.UserId == request.UserId, cancellationToken)
            ?? throw new NotFoundException("Album", request.AlbumId);

        var existingPhotoIds = await _db.AlbumPhotos
            .Where(ap => ap.AlbumId == request.AlbumId)
            .Select(ap => ap.PhotoId)
            .ToListAsync(cancellationToken);

        var maxSort = existingPhotoIds.Count > 0
            ? await _db.AlbumPhotos
                .Where(ap => ap.AlbumId == request.AlbumId)
                .MaxAsync(ap => ap.SortOrder, cancellationToken)
            : 0;

        var added = 0;
        foreach (var photoId in request.PhotoIds)
        {
            if (existingPhotoIds.Contains(photoId))
                continue;

            // Same owner filter as the album lookup above: a photo belonging to
            // another user is treated as not found and silently skipped, not added.
            var photoExists = await _db.Photos
                .AnyAsync(p => p.Id == photoId && p.UserId == request.UserId, cancellationToken);
            if (!photoExists)
                continue;

            _db.AlbumPhotos.Add(new AlbumPhoto
            {
                AlbumId = request.AlbumId,
                PhotoId = photoId,
                SortOrder = ++maxSort,
            });
            added++;
        }

        if (added > 0)
        {
            album.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync(cancellationToken);
        }

        return added;
    }
}
