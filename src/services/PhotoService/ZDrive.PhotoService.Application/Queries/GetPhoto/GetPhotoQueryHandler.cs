using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.DTOs;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.Shared.Exceptions;

namespace ZDrive.PhotoService.Application.Queries.GetPhoto;

public sealed class GetPhotoQueryHandler : IRequestHandler<GetPhotoQuery, PhotoDto>
{
    private readonly IPhotoDbContext _db;

    public GetPhotoQueryHandler(IPhotoDbContext db) => _db = db;

    public async Task<PhotoDto> Handle(GetPhotoQuery request, CancellationToken cancellationToken)
    {
        var photo = await _db.Photos.AsNoTracking()
            .FirstOrDefaultAsync(
                p => p.Id == request.PhotoId
                     && p.UserId == request.UserId
                     && p.TenantId == request.TenantId,
                cancellationToken)
            ?? throw new NotFoundException("Photo", request.PhotoId);

        return photo.ToDto();
    }
}
