using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.PhotoService.Application.Commands.DeleteAlbum;

public sealed class DeleteAlbumCommandHandler : IRequestHandler<DeleteAlbumCommand, bool>
{
    private readonly IPhotoDbContext _db;

    public DeleteAlbumCommandHandler(IPhotoDbContext db) => _db = db;

    public async Task<bool> Handle(DeleteAlbumCommand request, CancellationToken cancellationToken)
    {
        var album = await _db.Albums
            .FirstOrDefaultAsync(a => a.Id == request.AlbumId && a.UserId == request.UserId && a.TenantId == request.TenantId, cancellationToken)
            ?? throw new NotFoundException("Album", request.AlbumId);

        // Remove all album-photo associations first
        var albumPhotos = await _db.AlbumPhotos
            .Where(ap => ap.AlbumId == request.AlbumId)
            .ToListAsync(cancellationToken);

        _db.AlbumPhotos.RemoveRange(albumPhotos);
        _db.Albums.Remove(album);
        await _db.SaveChangesAsync(cancellationToken);

        return true;
    }
}
