using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.PhotoService.Application.Commands.RemovePhotoFromAlbum;

public sealed class RemovePhotoFromAlbumCommandHandler : IRequestHandler<RemovePhotoFromAlbumCommand, bool>
{
    private readonly IPhotoDbContext _db;

    public RemovePhotoFromAlbumCommandHandler(IPhotoDbContext db) => _db = db;

    public async Task<bool> Handle(RemovePhotoFromAlbumCommand request, CancellationToken cancellationToken)
    {
        // Verify album ownership
        var albumExists = await _db.Albums
            .AnyAsync(a => a.Id == request.AlbumId && a.UserId == request.UserId && a.TenantId == request.TenantId, cancellationToken);
        if (!albumExists)
            throw new NotFoundException("Album", request.AlbumId);

        var albumPhoto = await _db.AlbumPhotos
            .FirstOrDefaultAsync(ap => ap.AlbumId == request.AlbumId && ap.PhotoId == request.PhotoId, cancellationToken);

        if (albumPhoto is null)
            return false;

        _db.AlbumPhotos.Remove(albumPhoto);
        await _db.SaveChangesAsync(cancellationToken);
        return true;
    }
}
