using ZDrive.PhotoService.Domain.Entities;

namespace ZDrive.PhotoService.Application.DTOs;

public static class MappingExtensions
{
    public static PhotoDto ToDto(this Photo photo) => new(
        photo.Id,
        photo.FileId,
        photo.UserId,
        photo.TenantId,
        photo.TakenAt,
        photo.Lat,
        photo.Lng,
        photo.CameraMake,
        photo.CameraModel,
        photo.Width,
        photo.Height,
        photo.Orientation,
        photo.QualityScore,
        photo.ProcessingStatus.ToString(),
        photo.OriginalFileName,
        photo.BlobPath,
        photo.CreatedAt,
        photo.ThumbnailsReady);

    public static AlbumDto ToDto(this Album album, int photoCount) => new(
        album.Id,
        album.UserId,
        album.TenantId,
        album.Name,
        album.Type.ToString(),
        album.CoverPhotoId,
        photoCount,
        album.CreatedAt,
        album.UpdatedAt);

    public static PhotoTagDto ToDto(this PhotoTag tag) => new(
        tag.Id,
        tag.PhotoId,
        tag.Tag,
        tag.Confidence,
        tag.Source.ToString());

    public static MemoryDto ToDto(this Memory memory) => new(
        memory.Id,
        memory.UserId,
        memory.Type.ToString(),
        memory.Title,
        memory.DateFrom,
        memory.DateTo,
        memory.PhotoIds,
        memory.Seen,
        memory.GeneratedAt);
}
