using MediatR;
using ZDrive.StorageService.Application.Interfaces;

namespace ZDrive.StorageService.Application.Commands.PutThumbnail;

public sealed class PutThumbnailCommandHandler : IRequestHandler<PutThumbnailCommand, bool>
{
    private readonly IBlobStorageService _blobStorage;

    public PutThumbnailCommandHandler(IBlobStorageService blobStorage) => _blobStorage = blobStorage;

    public async Task<bool> Handle(PutThumbnailCommand request, CancellationToken cancellationToken)
    {
        await _blobStorage.UploadThumbnailAsync(
            request.TenantId, request.UserId, request.PhotoId, request.Version, request.Size, request.Content, cancellationToken);
        return true;
    }
}
