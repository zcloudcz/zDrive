using MediatR;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.PhotoService.Domain.Entities;

namespace ZDrive.PhotoService.Application.Commands.CreateAlbum;

public sealed class CreateAlbumCommandHandler : IRequestHandler<CreateAlbumCommand, AlbumDto>
{
    private readonly IPhotoDbContext _db;

    public CreateAlbumCommandHandler(IPhotoDbContext db) => _db = db;

    public async Task<AlbumDto> Handle(CreateAlbumCommand request, CancellationToken cancellationToken)
    {
        var album = new Album
        {
            Id = Guid.NewGuid(),
            UserId = request.UserId,
            TenantId = request.TenantId,
            Name = request.Name,
        };

        _db.Albums.Add(album);
        await _db.SaveChangesAsync(cancellationToken);

        return album.ToDto(0);
    }
}
