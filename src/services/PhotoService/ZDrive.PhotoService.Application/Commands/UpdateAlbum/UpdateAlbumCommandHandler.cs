using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.PhotoService.Application.Commands.UpdateAlbum;

public sealed class UpdateAlbumCommandHandler : IRequestHandler<UpdateAlbumCommand, AlbumDto>
{
    private readonly IPhotoDbContext _db;

    public UpdateAlbumCommandHandler(IPhotoDbContext db) => _db = db;

    public async Task<AlbumDto> Handle(UpdateAlbumCommand request, CancellationToken cancellationToken)
    {
        var album = await _db.Albums
            .FirstOrDefaultAsync(a => a.Id == request.AlbumId && a.UserId == request.UserId && a.TenantId == request.TenantId, cancellationToken)
            ?? throw new NotFoundException("Album", request.AlbumId);

        if (request.Name is not null)
            album.Name = request.Name;

        if (request.CoverPhotoId.HasValue)
        {
            var coverOwned = await _db.Photos.AnyAsync(
                p => p.Id == request.CoverPhotoId.Value && p.UserId == request.UserId && p.TenantId == request.TenantId,
                cancellationToken);
            if (!coverOwned)
                throw new NotFoundException("Photo", request.CoverPhotoId.Value);

            album.CoverPhotoId = request.CoverPhotoId.Value;
        }

        album.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(cancellationToken);

        var photoCount = await _db.AlbumPhotos.CountAsync(ap => ap.AlbumId == album.Id, cancellationToken);
        return album.ToDto(photoCount);
    }
}
