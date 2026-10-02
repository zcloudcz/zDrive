using MediatR;

namespace ZDrive.PhotoService.Application.Queries.GetPhotoThumbnail;

public sealed record GetPhotoThumbnailQuery(
    Guid UserId,
    Guid TenantId,
    Guid PhotoId,
    int Size,
    string? IfNoneMatch = null) : IRequest<PhotoThumbnailDto>;

/// <param name="Content">Null when <paramref name="NotModified"/>.</param>
public sealed record PhotoThumbnailDto(string ETag, bool NotModified, Stream? Content);
