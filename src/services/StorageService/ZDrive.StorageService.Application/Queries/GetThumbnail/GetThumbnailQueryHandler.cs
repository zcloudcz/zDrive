using MediatR;
using ZDrive.Shared.Exceptions;
using ZDrive.StorageService.Application.Interfaces;

namespace ZDrive.StorageService.Application.Queries.GetThumbnail;

public sealed class GetThumbnailQueryHandler : IRequestHandler<GetThumbnailQuery, Stream>
{
    private readonly IBlobStorageService _blobStorage;

    public GetThumbnailQueryHandler(IBlobStorageService blobStorage) => _blobStorage = blobStorage;

    public async Task<Stream> Handle(GetThumbnailQuery request, CancellationToken cancellationToken)
    {
        var stream = await _blobStorage.DownloadThumbnailAsync(
            request.TenantId, request.UserId, request.PhotoId, request.Version, request.Size, cancellationToken);

        return stream ?? throw new NotFoundException("Thumbnail", request.PhotoId);
    }
}
