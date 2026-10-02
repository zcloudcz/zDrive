using MediatR;
using ZDrive.StorageService.Application.Interfaces;

namespace ZDrive.StorageService.Application.Commands.DeleteThumbnails;

public sealed class DeleteThumbnailsCommandHandler : IRequestHandler<DeleteThumbnailsCommand, bool>
{
    private readonly IBlobStorageService _blobStorage;

    public DeleteThumbnailsCommandHandler(IBlobStorageService blobStorage) => _blobStorage = blobStorage;

    public async Task<bool> Handle(DeleteThumbnailsCommand request, CancellationToken cancellationToken)
    {
        await _blobStorage.DeleteThumbnailsAsync(request.TenantId, request.UserId, request.PhotoId, cancellationToken);
        return true;
    }
}
