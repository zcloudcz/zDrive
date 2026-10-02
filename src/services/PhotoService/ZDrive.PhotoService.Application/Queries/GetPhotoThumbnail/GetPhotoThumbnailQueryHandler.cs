using MediatR;
using Microsoft.EntityFrameworkCore;
using ZDrive.PhotoService.Application.Common;
using ZDrive.PhotoService.Application.Interfaces;
using ZDrive.PhotoService.Application.Interfaces.Ingest;
using ZDrive.PhotoService.Domain.Enums;
using ZDrive.Shared.Exceptions;

namespace ZDrive.PhotoService.Application.Queries.GetPhotoThumbnail;

public sealed class GetPhotoThumbnailQueryHandler : IRequestHandler<GetPhotoThumbnailQuery, PhotoThumbnailDto>
{
    private readonly IPhotoDbContext _db;
    private readonly IThumbnailStore _store;

    public GetPhotoThumbnailQueryHandler(IPhotoDbContext db, IThumbnailStore store)
    {
        _db = db;
        _store = store;
    }

    public async Task<PhotoThumbnailDto> Handle(GetPhotoThumbnailQuery request, CancellationToken cancellationToken)
    {
        // Hidden (trashed) photos are excluded by the entity's query filter.
        var photo = await _db.Photos.AsNoTracking()
            .Where(p => p.Id == request.PhotoId
                && p.UserId == request.UserId
                && p.TenantId == request.TenantId
                && p.ProcessingStatus == ProcessingStatus.Processed
                && p.ThumbnailsReady)
            .Select(p => new { p.ProcessedManifestHash })
            .FirstOrDefaultAsync(cancellationToken)
            ?? throw new NotFoundException("Thumbnail", request.PhotoId);

        // Derived from the row, so a 304 never has to touch blob storage; a new
        // version changes the manifest hash and therefore the tag.
        var version = ThumbnailVersion.Of(photo.ProcessedManifestHash ?? "");
        var etag = $"\"{request.PhotoId:N}-{request.Size}-{version}\"";

        if (request.IfNoneMatch is { Length: > 0 } header
            && header.Split(',').Any(t => t.Trim() == etag || t.Trim() == "*"))
            return new PhotoThumbnailDto(etag, true, null);

        var stream = await _store.OpenAsync(
            request.TenantId, request.UserId, request.PhotoId, version, request.Size, cancellationToken)
            ?? throw new NotFoundException("Thumbnail", request.PhotoId);

        return new PhotoThumbnailDto(etag, false, stream);
    }
}
